import { createHash, randomUUID } from "node:crypto";
import { getTurso } from "../turso";
import { newsLocaleForUser } from "../news/user-locale";

export type RecommendedArticle = {
  id: string;
  url: string;
  title: string;
  description: string | null;
  imageURL: string | null;
  source: string;
  publishedAt: string;
  topicIDs: string[];
  rank: number;
  reason: string;
  reasonEN: string;
};

type CandidateRow = {
  id: string;
  url: string;
  title: string;
  description: string | null;
  imageURL: string | null;
  source: string;
  publishedAt: string;
  qualityScore: number;
  topicID: string;
  language: string;
  country: string | null;
};

export function tokyoEditionDate(now = new Date()): string {
  return editionDateForTimeZone(now, "Asia/Tokyo");
}

export type DailyEditionTarget = {
  userID: string;
  timeZone: string;
  editionDate: string;
  language: "japanese" | "english";
  sourceCountry: string;
  topicIDs: string[];
};

export type DailyEditionBuildOptions = {
  forceRebuild?: boolean;
  markFallback?: boolean;
};

export function isDailyEditionCatchUpTime(now: Date, timeZone: string): boolean {
  const parts = localDateParts(now, timeZone);
  const hour = Number(parts.hour);
  // The Vercel cron runs every five minutes. Treat the full 17:00 hour in the
  // user's saved timezone as a catch-up window, then skip users already handled
  // by the scheduled job so transient API errors do not make the day fail.
  return hour === 17;
}

export function dailyEditionStatusForSelection(
  selectedCount: number,
  markFallback = false,
): "ready" | "fallback" | "failed" {
  if (selectedCount === 0) return "failed";
  return markFallback || selectedCount < 5 ? "fallback" : "ready";
}

export function editionDateForTimeZone(now: Date, timeZone: string): string {
  const parts = localDateParts(now, timeZone);
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export async function dueDailyEditionTargets(now = new Date()): Promise<DailyEditionTarget[]> {
  const rows = (await getTurso().all(
    `SELECT u.id AS userID, COALESCE(p.time_zone, 'Asia/Tokyo') AS timeZone
     FROM users u LEFT JOIN user_recommendation_profiles p ON p.user_id = u.id
     ORDER BY u.created_at`,
  )) as Array<{ userID: string; timeZone?: string | null }>;
  const targets = await Promise.all(rows.map(async (row) => {
    const timeZone = validTimeZone(row.timeZone);
    const parts = localDateParts(now, timeZone);
    if (!isDailyEditionCatchUpTime(now, timeZone)) return null;
    if (await scheduledDailyEditionAlreadyCompleted(row.userID, `${parts.year}-${parts.month}-${parts.day}`, timeZone)) {
      return null;
    }
    const locale = await newsLocaleForUser(row.userID);
    return {
      userID: row.userID,
      timeZone,
      editionDate: `${parts.year}-${parts.month}-${parts.day}`,
      language: locale.language,
      sourceCountry: locale.sourceCountry,
      topicIDs: locale.topicIDs,
    } satisfies DailyEditionTarget;
  }));
  return targets.filter((target): target is DailyEditionTarget => target !== null);
}

async function scheduledDailyEditionAlreadyCompleted(
  userID: string,
  editionDate: string,
  timeZone: string,
): Promise<boolean> {
  const row = (await getTurso().get(
    `SELECT e.status, e.auto_cast_status AS autoCastStatus,
            COALESCE(e.generated_at, e.updated_at) AS generatedAt,
            (SELECT COUNT(*) FROM daily_news_edition_items i WHERE i.edition_id = e.id) AS itemCount
     FROM daily_news_editions e
     WHERE e.user_id = ? AND e.edition_date = ? LIMIT 1`,
    userID, editionDate,
  )) as { status?: string; autoCastStatus?: string | null; generatedAt?: string | null; itemCount?: number } | null;
  if (!row?.generatedAt || (row.itemCount ?? 0) < 5 || row.status === "failed") return false;
  const generatedAt = new Date(row.generatedAt);
  if (Number.isNaN(generatedAt.valueOf())) return false;
  const generatedParts = localDateParts(generatedAt, timeZone);
  const generatedEditionDate = `${generatedParts.year}-${generatedParts.month}-${generatedParts.day}`;
  const generatedAfterScheduleStart = generatedEditionDate === editionDate && Number(generatedParts.hour) >= 17;
  // A regular app feed GET can lazily build today's edition too. That path
  // leaves auto_cast_status as "disabled", while this scheduled cron updates it
  // to queued/skipped/processing/ready after enqueueing or eligibility checks.
  return generatedAfterScheduleStart && row.autoCastStatus !== "disabled";
}

export async function buildDailyEdition(
  userID: string,
  editionDate = tokyoEditionDate(),
  options: DailyEditionBuildOptions | boolean = {},
): Promise<string> {
  const { forceRebuild, markFallback } = normalizeBuildOptions(options);
  const database = getTurso();
  const userLocale = await newsLocaleForUser(userID);
  const existing = (await database.get(
    "SELECT id, status FROM daily_news_editions WHERE user_id = ? AND edition_date = ? LIMIT 1",
    userID, editionDate,
  )) as { id?: string; status?: string } | null;

  const now = new Date().toISOString();
  let activeEditionID = existing?.id;
  if (!activeEditionID) {
    const editionID = randomUUID();
    await database.run(
      `INSERT OR IGNORE INTO daily_news_editions
        (id, user_id, edition_date, status, auto_cast_status, created_at, updated_at)
       VALUES (?, ?, ?, 'building', 'disabled', ?, ?)`,
      editionID, userID, editionDate, now, now,
    );
    const resolved = (await database.get(
      "SELECT id FROM daily_news_editions WHERE user_id = ? AND edition_date = ? LIMIT 1",
      userID, editionDate,
    )) as { id?: string } | null;
    activeEditionID = resolved?.id ?? editionID;
  }
  const itemCount = (await database.get(
    `SELECT COUNT(*) AS count
     FROM daily_news_edition_items i
     WHERE i.edition_id = ?
       AND NOT EXISTS (
         SELECT 1 FROM recommendation_events e
         WHERE e.user_id = ? AND e.article_id = i.article_id AND e.event_type = 'dislike'
       )`,
    activeEditionID, userID,
  )) as { count?: number } | null;
  if ((itemCount?.count ?? 0) >= 5 && !forceRebuild) {
    if (markFallback && existing?.status !== "fallback") {
      await database.run(
        "UPDATE daily_news_editions SET status = 'fallback', updated_at = ? WHERE id = ?",
        now, activeEditionID,
      );
    }
    return activeEditionID;
  }
  if (forceRebuild || (itemCount?.count ?? 0) < 5) {
    await database.run("DELETE FROM daily_news_edition_items WHERE edition_id = ?", activeEditionID);
  }

  await database.run(
    "UPDATE daily_news_editions SET status = 'building', updated_at = ? WHERE id = ?",
    now, activeEditionID,
  );

  const settings = (await database.get(
    "SELECT personalization_enabled AS enabled FROM user_recommendation_profiles WHERE user_id = ?",
    userID,
  )) as { enabled?: number } | null;
  const personalizationEnabled = settings?.enabled !== 0;

  const preferences = personalizationEnabled ? (await database.all(
    `SELECT topic_id AS topicID, preference, weight
     FROM user_topic_preferences WHERE user_id = ?`,
    userID,
  )) as Array<{ topicID: string; preference: string; weight: number }> : [];
  const customInterests = personalizationEnabled ? (await database.all(
    `SELECT label, matched_topic_id AS topicID
     FROM user_custom_interests WHERE user_id = ?`,
    userID,
  )) as Array<{ label: string; topicID: string }> : [];
  const liked = new Map(preferences.filter((item) => item.preference === "like").map((item) => [item.topicID, item.weight]));
  for (const interest of customInterests) {
    liked.set(interest.topicID, Math.max(liked.get(interest.topicID) ?? 0, 0.8));
  }
  const avoided = new Set(preferences.filter((item) => item.preference === "avoid").map((item) => item.topicID));
  const memories = personalizationEnabled ? (await database.all(
    `SELECT value AS topicID, polarity, weight
     FROM user_memory_items WHERE user_id = ? AND kind = 'topic'
       AND (expires_at IS NULL OR expires_at > ?)`,
    userID, now,
  )) as Array<{ topicID: string; polarity: string; weight: number }> : [];
  const memoryWeight = new Map(memories.map((item) => [item.topicID, (item.polarity === "negative" ? -1 : 1) * item.weight]));
  const candidates = (await database.all(
    `SELECT a.id, a.original_url AS url, a.title, a.description,
            a.image_url AS imageURL, a.source_domain AS source,
            a.published_at AS publishedAt, a.quality_score AS qualityScore,
            a.language, a.country, t.topic_id AS topicID
     FROM news_articles a
     JOIN news_article_topics t ON t.article_id = a.id
     WHERE a.expires_at > ?
       AND NOT EXISTS (
         SELECT 1 FROM recommendation_events e
         WHERE e.user_id = ? AND e.article_id = a.id
           AND e.event_type IN ('dislike', 'mute_topic', 'mute_source')
       )
     ORDER BY a.published_at DESC
     LIMIT 500`,
    now, userID,
  )) as CandidateRow[];

  const grouped = groupCandidates(candidates);
  const scored = [...grouped.values()].map((article) => {
    const likedWeight = Math.max(0, ...article.topicIDs.map((id) => liked.get(id) ?? 0));
    const learnedWeight = Math.max(-1, ...article.topicIDs.map((id) => memoryWeight.get(id) ?? 0));
    const hasAvoided = article.topicIDs.some((id) => avoided.has(id));
    const hoursOld = Math.max(0, (Date.now() - Date.parse(article.publishedAt)) / 3_600_000);
    const freshness = Math.max(0, 1 - hoursOld / 96);
    const discovery = stableRandom(`${userID}:${editionDate}:${article.id}`);
    const languageMatch = article.language.toLocaleLowerCase().startsWith(userLocale.language === "english" ? "english" : "japanese") ? 1 : 0;
    const regionMatch = normalizeCountry(article.country) === normalizeCountry(userLocale.sourceCountry) ? 1 : 0;
    const searchableText = `${article.title} ${article.description ?? ""}`;
    const customMatch = Math.max(0, ...customInterests.map((interest) => customInterestMatch(searchableText, interest.label)));
    return {
      ...article,
      likedWeight,
      customMatch,
      languageMatch,
      regionMatch,
      score: likedWeight * 4 + customMatch * 5 + learnedWeight * 2.5 + freshness * 1.5
        + languageMatch * 1.5 + regionMatch * 0.5
        + article.qualityScore + discovery * 0.8 - (hasAvoided ? 10 : 0),
    };
  });

  const selected: typeof scored = [];
  const add = (items: typeof scored, maximum: number) => {
    for (const item of items.sort((a, b) => b.score - a.score)) {
      if (selected.length >= maximum) break;
      if (selected.some((existingItem) => existingItem.id === item.id || existingItem.source === item.source)) continue;
      selected.push(item);
    }
  };
  // Fill from explicit interests first. Discovery is only used after the
  // user's selected topics have been exhausted or do not have enough items.
  add(scored.filter((item) => item.customMatch > 0), 5);
  add(scored.filter((item) => item.likedWeight > 0), 5);
  add(scored.filter((item) => item.likedWeight > 0 && !selected.some((picked) => picked.id === item.id)), 5);
  add(scored.filter((item) => item.likedWeight === 0), 5);
  add(scored, 5);

  if (selected.length === 0) {
    await database.run(
      "UPDATE daily_news_editions SET status = ?, updated_at = ? WHERE id = ?",
      dailyEditionStatusForSelection(selected.length, markFallback), new Date().toISOString(), activeEditionID,
    );
    return activeEditionID;
  }

  const statements = selected.slice(0, 5).map((article, index) => {
    const customInterest = article.customMatch > 0;
    const discovery = article.likedWeight === 0 && !customInterest;
    return {
      sql: `INSERT OR IGNORE INTO daily_news_edition_items
        (edition_id, article_id, rank, score, reason_code, reason_text_ja, reason_text_en)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
      args: [activeEditionID, article.id, index + 1, article.score,
        discovery ? "discovery" : customInterest ? "custom_interest" : "selected_topic",
        discovery ? "興味を広げる新しいトピックです" : customInterest ? "追加した興味ジャンルに特に近い記事です" : "選択した興味ジャンルに関連しています",
        discovery ? "A discovery outside your usual topics" : customInterest ? "Closely matches an interest you added" : "Related to one of your selected interests"],
    };
  });
  statements.push({
    sql: `UPDATE daily_news_editions SET status = ?, generated_at = ?, updated_at = ? WHERE id = ?`,
    args: [dailyEditionStatusForSelection(selected.length, markFallback), now, now, activeEditionID],
  });
  await database.batch(statements, "immediate");
  return activeEditionID;
}

function customInterestMatch(text: string, label: string): number {
  const normalizedText = text.normalize("NFKC").toLocaleLowerCase("ja-JP");
  const normalizedLabel = label.normalize("NFKC").toLocaleLowerCase("ja-JP");
  const terms = new Set([normalizedLabel, ...expandedInterestTerms(normalizedLabel)]);
  let matches = 0;
  for (const term of terms) {
    if (term.length >= 2 && normalizedText.includes(term)) matches += 1;
  }
  return Math.min(1, matches / Math.min(3, Math.max(1, terms.size)));
}

function expandedInterestTerms(label: string): string[] {
  if (["生成ai", "generative ai", "genai", "生成系ai"].some((term) => label.includes(term))) {
    return ["生成ai", "generative ai", "genai", "llm", "大規模言語モデル", "chatgpt", "claude", "gemini"];
  }
  if (["ai", "人工知能", "機械学習"].some((term) => label.includes(term))) {
    return ["ai", "人工知能", "機械学習", "machine learning", "deep learning"];
  }
  return [];
}

export async function buildDailyEditionsForUsers(
  targets: DailyEditionTarget[],
  options: DailyEditionBuildOptions = {},
): Promise<{ users: number; ready: number; failed: number }> {
  console.info("[daily-news] edition build started", { users: targets.length });
  let ready = 0;
  let failed = 0;
  for (const target of targets) {
    const editionID = await buildDailyEdition(target.userID, target.editionDate, options);
    const row = (await getTurso().get("SELECT status FROM daily_news_editions WHERE id = ?", editionID)) as { status?: string } | null;
    if (row?.status === "ready" || row?.status === "fallback") ready += 1;
    else failed += 1;
    console.info("[daily-news] user edition built", {
      editionDate: target.editionDate,
      timeZone: target.timeZone,
      userID: target.userID,
      editionID,
      status: row?.status ?? "missing",
    });
  }
  const result = { users: targets.length, ready, failed };
  console.info("[daily-news] edition build completed", result);
  return result;
}

export async function buildDailyEditionsForAllUsers(now = new Date()): Promise<{ users: number; ready: number; failed: number }> {
  const targets = (await getTurso().all(
    `SELECT u.id AS userID, COALESCE(p.time_zone, 'Asia/Tokyo') AS timeZone
     FROM users u LEFT JOIN user_recommendation_profiles p ON p.user_id = u.id
     ORDER BY u.created_at`,
  )) as Array<{ userID: string; timeZone?: string | null }>;
  const mappedTargets = await Promise.all(targets.map(async (row) => {
    const timeZone = validTimeZone(row.timeZone);
    const locale = await newsLocaleForUser(row.userID);
    return {
      userID: row.userID,
      timeZone,
      editionDate: editionDateForTimeZone(now, timeZone),
      language: locale.language,
      sourceCountry: locale.sourceCountry,
      topicIDs: locale.topicIDs,
    } satisfies DailyEditionTarget;
  }));
  return buildDailyEditionsForUsers(mappedTargets);
}

export async function dailyEditionDateForUser(userID: string, now = new Date()): Promise<string> {
  const row = (await getTurso().get(
    `SELECT COALESCE(time_zone, 'Asia/Tokyo') AS timeZone
     FROM user_recommendation_profiles WHERE user_id = ? LIMIT 1`,
    userID,
  )) as { timeZone?: string | null } | null;
  return editionDateForTimeZone(now, validTimeZone(row?.timeZone));
}

export async function dailyEditionForUser(userID: string, editionDate = tokyoEditionDate()): Promise<{ id: string; status: string; castID: string | null; autoCastStatus: string; generatedAt: string | null; items: RecommendedArticle[] }> {
  const editionID = await buildDailyEdition(userID, editionDate);
  const edition = (await getTurso().get(
    `SELECT status, cast_id AS castID, auto_cast_status AS autoCastStatus,
            COALESCE(generated_at, updated_at) AS generatedAt
     FROM daily_news_editions WHERE id = ?`,
    editionID,
  )) as { status?: string; castID?: string | null; autoCastStatus?: string; generatedAt?: string | null } | null;
  let items = await loadEditionItems(editionID, userID);
  if (items.length < 5) {
    const fallback = (await getTurso().get(
      `SELECT e.id, e.cast_id AS castID, e.auto_cast_status AS autoCastStatus,
              COALESCE(e.generated_at, e.updated_at) AS generatedAt
       FROM daily_news_editions e
       WHERE e.user_id = ? AND e.edition_date < ?
         AND (SELECT COUNT(*) FROM daily_news_edition_items i
              WHERE i.edition_id = e.id
                AND NOT EXISTS (
                  SELECT 1 FROM recommendation_events re
                  WHERE re.user_id = ? AND re.article_id = i.article_id AND re.event_type = 'dislike'
                )) = 5
       ORDER BY e.edition_date DESC LIMIT 1`,
      userID, editionDate, userID,
    )) as { id?: string; castID?: string | null; autoCastStatus?: string; generatedAt?: string | null } | null;
    if (fallback?.id) {
      items = await loadEditionItems(fallback.id, userID);
      return {
        id: fallback.id,
        status: "fallback",
        castID: fallback.castID ?? null,
        autoCastStatus: fallback.autoCastStatus ?? "disabled",
        generatedAt: fallback.generatedAt ?? null,
        items,
      };
    }
  }
  return {
    id: editionID,
    status: edition?.status ?? "failed",
    castID: edition?.castID ?? null,
    autoCastStatus: edition?.autoCastStatus ?? "disabled",
    generatedAt: edition?.generatedAt ?? null,
    items,
  };
}

async function loadEditionItems(editionID: string, userID: string): Promise<RecommendedArticle[]> {
  const rows = (await getTurso().all(
    `SELECT a.id, a.original_url AS url, a.title, a.description, a.image_url AS imageURL,
            a.source_domain AS source, a.published_at AS publishedAt, i.rank,
            i.reason_text_ja AS reason, i.reason_text_en AS reasonEN,
            GROUP_CONCAT(t.topic_id) AS topicIDs
     FROM daily_news_edition_items i
     JOIN news_articles a ON a.id = i.article_id
     LEFT JOIN news_article_topics t ON t.article_id = a.id
     WHERE i.edition_id = ?
       AND NOT EXISTS (
         SELECT 1 FROM recommendation_events e
         WHERE e.user_id = ? AND e.article_id = a.id AND e.event_type = 'dislike'
       )
     GROUP BY a.id, i.rank
     ORDER BY i.rank`,
    editionID, userID,
  )) as Array<Omit<RecommendedArticle, "topicIDs"> & { topicIDs: string | null }>;
  return rows.map((row) => ({ ...row, topicIDs: row.topicIDs?.split(",") ?? [] }));
}

function normalizeBuildOptions(options: DailyEditionBuildOptions | boolean): Required<DailyEditionBuildOptions> {
  if (typeof options === "boolean") {
    return { forceRebuild: options, markFallback: false };
  }
  return {
    forceRebuild: options.forceRebuild === true,
    markFallback: options.markFallback === true,
  };
}

function validTimeZone(value?: string | null): string {
  const candidate = value?.trim() || "Asia/Tokyo";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: candidate }).format();
    return candidate;
  } catch {
    return "Asia/Tokyo";
  }
}

function localDateParts(now: Date, timeZone: string): { year: string; month: string; day: string; hour: string; minute: string } {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: validTimeZone(timeZone),
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(now);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return {
    year: values.year,
    month: values.month,
    day: values.day,
    hour: values.hour,
    minute: values.minute,
  };
}

function groupCandidates(rows: CandidateRow[]): Map<string, Omit<CandidateRow, "topicID"> & { topicIDs: string[] }> {
  const result = new Map<string, Omit<CandidateRow, "topicID"> & { topicIDs: string[] }>();
  for (const row of rows) {
    const current = result.get(row.id)
      ?? [...result.values()].find((candidate) => sameStory(candidate.title, row.title));
    if (current) current.topicIDs.push(row.topicID);
    else result.set(row.id, { ...row, topicIDs: [row.topicID] });
  }
  return result;
}

function sameStory(left: string, right: string): boolean {
  const a = normalizeTitle(left);
  const b = normalizeTitle(right);
  if (!a || !b) return false;
  if (a === b) return true;
  const shorter = a.length <= b.length ? a : b;
  const longer = a.length <= b.length ? b : a;
  if (shorter.length >= 16 && longer.includes(shorter)) return true;
  const leftTokens = titleTokens(a);
  const rightTokens = titleTokens(b);
  if (leftTokens.size < 4 || rightTokens.size < 4) return false;
  const intersection = [...leftTokens].filter((token) => rightTokens.has(token)).length;
  return intersection / Math.min(leftTokens.size, rightTokens.size) >= 0.78;
}

function normalizeTitle(value: string): string {
  return value.normalize("NFKC").toLocaleLowerCase().replace(/[\s\p{P}\p{S}]+/gu, "");
}

function titleTokens(value: string): Set<string> {
  if (/[\u3040-\u30ff\u3400-\u9fff]/u.test(value)) {
    return new Set(Array.from({ length: Math.max(0, value.length - 1) }, (_, index) => value.slice(index, index + 2)));
  }
  return new Set(value.split(/[^a-z0-9]+/i).filter((token) => token.length > 1));
}

function stableRandom(seed: string): number {
  return Number.parseInt(createHash("sha256").update(seed).digest("hex").slice(0, 8), 16) / 0xffffffff;
}

function normalizeCountry(value?: string | null): string {
  return value?.toLocaleLowerCase().replace(/[^a-z]/g, "") ?? "";
}

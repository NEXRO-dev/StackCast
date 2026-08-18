import { createHash, randomUUID } from "node:crypto";
import { getTurso } from "../turso";

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
};

export function tokyoEditionDate(now = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tokyo", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now);
}

export async function buildDailyEdition(userID: string, editionDate = tokyoEditionDate()): Promise<string> {
  const database = getTurso();
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
    "SELECT COUNT(*) AS count FROM daily_news_edition_items WHERE edition_id = ?",
    activeEditionID,
  )) as { count?: number } | null;
  if ((itemCount?.count ?? 0) >= 5) return activeEditionID;

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
            t.topic_id AS topicID
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
    const searchableText = `${article.title} ${article.description ?? ""}`;
    const customMatch = Math.max(0, ...customInterests.map((interest) => customInterestMatch(searchableText, interest.label)));
    return {
      ...article,
      likedWeight,
      customMatch,
      score: likedWeight * 4 + customMatch * 5 + learnedWeight * 2.5 + freshness * 1.5
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
  add(scored.filter((item) => item.customMatch > 0), 3);
  add(scored.filter((item) => item.likedWeight > 0), 3);
  add(scored.filter((item) => item.likedWeight > 0 && !selected.some((picked) => picked.id === item.id)), 4);
  add(scored.filter((item) => item.likedWeight === 0), 5);
  add(scored, 5);

  if (selected.length === 0) {
    await database.run(
      "UPDATE daily_news_editions SET status = 'failed', updated_at = ? WHERE id = ?",
      new Date().toISOString(), activeEditionID,
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
    args: [selected.length >= 5 ? "ready" : "fallback", now, now, activeEditionID],
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

export async function buildDailyEditionsForAllUsers(editionDate = tokyoEditionDate()): Promise<{ users: number; ready: number; failed: number }> {
  const users = (await getTurso().all("SELECT id FROM users ORDER BY created_at")) as Array<{ id: string }>;
  let ready = 0;
  let failed = 0;
  for (const user of users) {
    const editionID = await buildDailyEdition(user.id, editionDate);
    const row = (await getTurso().get("SELECT status FROM daily_news_editions WHERE id = ?", editionID)) as { status?: string } | null;
    if (row?.status === "ready" || row?.status === "fallback") ready += 1;
    else failed += 1;
  }
  return { users: users.length, ready, failed };
}

export async function dailyEditionForUser(userID: string, editionDate = tokyoEditionDate()): Promise<{ id: string; status: string; castID: string | null; autoCastStatus: string; items: RecommendedArticle[] }> {
  const editionID = await buildDailyEdition(userID, editionDate);
  const edition = (await getTurso().get(
    `SELECT status, cast_id AS castID, auto_cast_status AS autoCastStatus FROM daily_news_editions WHERE id = ?`,
    editionID,
  )) as { status?: string; castID?: string | null; autoCastStatus?: string } | null;
  let items = await loadEditionItems(editionID);
  if (items.length < 5) {
    const fallback = (await getTurso().get(
      `SELECT e.id, e.cast_id AS castID, e.auto_cast_status AS autoCastStatus
       FROM daily_news_editions e
       WHERE e.user_id = ? AND e.edition_date < ?
         AND (SELECT COUNT(*) FROM daily_news_edition_items i WHERE i.edition_id = e.id) = 5
       ORDER BY e.edition_date DESC LIMIT 1`,
      userID, editionDate,
    )) as { id?: string; castID?: string | null; autoCastStatus?: string } | null;
    if (fallback?.id) {
      items = await loadEditionItems(fallback.id);
      return {
        id: fallback.id,
        status: "fallback",
        castID: fallback.castID ?? null,
        autoCastStatus: fallback.autoCastStatus ?? "disabled",
        items,
      };
    }
  }
  return {
    id: editionID,
    status: edition?.status ?? "failed",
    castID: edition?.castID ?? null,
    autoCastStatus: edition?.autoCastStatus ?? "disabled",
    items,
  };
}

async function loadEditionItems(editionID: string): Promise<RecommendedArticle[]> {
  const rows = (await getTurso().all(
    `SELECT a.id, a.original_url AS url, a.title, a.description, a.image_url AS imageURL,
            a.source_domain AS source, a.published_at AS publishedAt, i.rank,
            i.reason_text_ja AS reason, i.reason_text_en AS reasonEN,
            GROUP_CONCAT(t.topic_id) AS topicIDs
     FROM daily_news_edition_items i
     JOIN news_articles a ON a.id = i.article_id
     LEFT JOIN news_article_topics t ON t.article_id = a.id
     WHERE i.edition_id = ?
     GROUP BY a.id, i.rank
     ORDER BY i.rank`,
    editionID,
  )) as Array<Omit<RecommendedArticle, "topicIDs"> & { topicIDs: string | null }>;
  return rows.map((row) => ({ ...row, topicIDs: row.topicIDs?.split(",") ?? [] }));
}

function groupCandidates(rows: CandidateRow[]): Map<string, Omit<CandidateRow, "topicID"> & { topicIDs: string[] }> {
  const result = new Map<string, Omit<CandidateRow, "topicID"> & { topicIDs: string[] }>();
  for (const row of rows) {
    const current = result.get(row.id);
    if (current) current.topicIDs.push(row.topicID);
    else result.set(row.id, { ...row, topicIDs: [row.topicID] });
  }
  return result;
}

function stableRandom(seed: string): number {
  return Number.parseInt(createHash("sha256").update(seed).digest("hex").slice(0, 8), 16) / 0xffffffff;
}

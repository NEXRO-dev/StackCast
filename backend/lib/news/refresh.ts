import { featureEnabled } from "../feature-flags";
import { getTurso } from "../turso";
import { GDELTProvider } from "./providers/gdelt";
import { OpenAIWebSearchProvider } from "./providers/openai-web-search";
import { upsertNewsCandidate } from "./repository";

type TopicRow = { id: string; query: string };
export const NEWS_POOL_COOLDOWN_MS = 6 * 60 * 60 * 1_000;

export type NewsRefreshOptions = {
  language?: "japanese" | "english";
  sourceCountry?: string;
  topicIDs?: string[];
  excludeTopicIDs?: string[];
  force?: boolean;
};

export type NewsRefreshResult = {
  topics: number;
  fetched: number;
  stored: number;
  failures: string[];
  cooldown: boolean;
};

export type NewsRefreshBuildDecision = {
  forceRebuild: boolean;
  markFallback: boolean;
};

export function newsRefreshIsWithinCooldown(
  latestSuccessfulFetchAt: string | null | undefined,
  now = new Date(),
  force = false,
  successfulArticleCount = 5,
): boolean {
  if (force || successfulArticleCount < 5 || !latestSuccessfulFetchAt) return false;
  const latestTimestamp = Date.parse(latestSuccessfulFetchAt);
  if (!Number.isFinite(latestTimestamp)) return false;
  const elapsed = now.getTime() - latestTimestamp;
  return elapsed >= 0 && elapsed < NEWS_POOL_COOLDOWN_MS;
}

export function newsRefreshProviderUnavailable(result: NewsRefreshResult): boolean {
  return !result.cooldown && result.stored === 0 && result.failures.length > 0;
}

export function newsRefreshProviderUnderfilled(result: NewsRefreshResult): boolean {
  return !result.cooldown && result.stored > 0 && result.stored < 5;
}

export function newsRefreshBuildDecision(result: NewsRefreshResult): NewsRefreshBuildDecision {
  const markFallback = newsRefreshProviderUnavailable(result) || newsRefreshProviderUnderfilled(result);
  return {
    forceRebuild: result.stored > 0 || markFallback,
    markFallback,
  };
}

/** GDELT first; one OpenAI request only when GDELT cannot fill five items. */
export async function refreshSharedNewsPool(options: NewsRefreshOptions = {}): Promise<NewsRefreshResult> {
  const topicIDs = [...new Set(options.topicIDs ?? [])];
  const filters = ["is_active = 1"];
  const args: string[] = [];
  if (topicIDs.length > 0) {
    filters.push(`id IN (${topicIDs.map(() => "?").join(", ")})`);
    args.push(...topicIDs);
  }
  const excludedTopicIDs = [...new Set(options.excludeTopicIDs ?? [])];
  if (excludedTopicIDs.length > 0) {
    filters.push(`id NOT IN (${excludedTopicIDs.map(() => "?").join(", ")})`);
    args.push(...excludedTopicIDs);
  }
  const topics = (await getTurso().all(
    `SELECT id, query_en AS query FROM recommendation_topics WHERE ${filters.join(" AND ")} ORDER BY sort_order`,
    ...args,
  )) as TopicRow[];
  const language = options.language ?? "japanese";
  const cooldownCutoff = new Date(Date.now() - NEWS_POOL_COOLDOWN_MS).toISOString();
  const latest = (await getTurso().get(
    `SELECT MAX(fetched_at) AS fetchedAt, COUNT(DISTINCT id) AS articleCount FROM news_articles
     WHERE provider IN (?, ?) AND LOWER(language) = LOWER(?)
       AND ((LOWER(country) = LOWER(?) AND ? IS NOT NULL) OR (country IS NULL AND ? IS NULL))
       AND fetched_at >= ?`,
    "gdelt", "openai-web-search", language, options.sourceCountry ?? null,
    options.sourceCountry ?? null, options.sourceCountry ?? null, cooldownCutoff,
  )) as { fetchedAt?: string | null; articleCount?: number } | null;
  if (newsRefreshIsWithinCooldown(latest?.fetchedAt, new Date(), options.force, latest?.articleCount ?? 0)) {
    console.info("[daily-news] shared pool refresh skipped", {
      reason: "cooldown", providers: ["gdelt", "openai-web-search"], topics: topics.length,
      lastFetchedAt: latest?.fetchedAt, articleCount: latest?.articleCount ?? 0,
      cooldownHours: NEWS_POOL_COOLDOWN_MS / 3_600_000,
    });
    return { topics: topics.length, fetched: 0, stored: 0, failures: [], cooldown: true };
  }

  const gdeltEnabled = featureEnabled("GDELT_PROVIDER_ENABLED");
  let fetched = 0;
  let stored = 0;
  const failures: string[] = [];
  console.info("[daily-news] shared pool refresh started", {
    provider: gdeltEnabled ? "gdelt" : "disabled", fallbackProvider: "openai-web-search", topics: topics.length,
    language, sourceCountry: options.sourceCountry ?? null,
  });

  if (gdeltEnabled) {
    const gdelt = new GDELTProvider();
    try {
      const candidates = await gdelt.searchTopics(topics.map((topic) => ({
        topicID: topic.id,
        query: topic.query,
        language,
        sourceCountry: options.sourceCountry,
        limit: 5,
      })));
      fetched += candidates.length;
      stored += await storeCandidates(topics[0]?.id ?? "", "gdelt", candidates, failures);
      console.info("[daily-news] gdelt combined refresh completed", {
        topics: topics.length,
        fetched: candidates.length,
        requests: 1,
      });
    } catch (error) {
      const details = errorDetails(error);
      failures.push(`combined:gdelt:${details.message}`);
      console.warn("[daily-news] gdelt combined refresh failed", {
        topics: topics.length,
        requests: 1,
        ...details,
      });
    }
  } else {
    console.info("[daily-news] gdelt refresh skipped", { reason: "feature_disabled" });
  }

  if (stored < 5 && process.env.OPENAI_NEWS_FALLBACK_ENABLED !== "false") {
    try {
      const fallback = new OpenAIWebSearchProvider();
      const candidates = await fallback.searchTopics(topics.map((topic) => ({
        topicID: topic.id, query: topic.query, language,
        sourceCountry: options.sourceCountry, limit: 5,
      })));
      fetched += candidates.length;
      stored += await storeCandidates(topics[0]?.id ?? "", "openai-web-search", candidates, failures);
      console.info("[daily-news] openai fallback refreshed", {
        fetched: candidates.length,
        stored,
        reason: gdeltEnabled ? "gdelt_underfilled" : "gdelt_disabled",
      });
    } catch (error) {
      const details = errorDetails(error);
      failures.push(`openai-fallback:${details.message}`);
      console.warn("[daily-news] openai fallback failed", details);
    }
  }

  const result: NewsRefreshResult = {
    topics: topics.length,
    fetched,
    stored,
    failures: failures.slice(0, 50),
    cooldown: false,
  };
  console.info("[daily-news] shared pool refresh completed", { ...result, failureCount: failures.length });
  return result;
}

async function storeCandidates(
  defaultTopicID: string,
  provider: string,
  candidates: Array<Parameters<typeof upsertNewsCandidate>[2]>,
  failures: string[],
): Promise<number> {
  let stored = 0;
  for (const candidate of candidates) {
    const topicID = candidate.topicID ?? defaultTopicID;
    if (!topicID) continue;
    try {
      await upsertNewsCandidate(topicID, provider, candidate);
      stored += 1;
    } catch (error) {
      failures.push(`${topicID}:${provider}:store:${error instanceof Error ? error.message : String(error)}`);
    }
  }
  return stored;
}

function errorDetails(error: unknown): { name: string; message: string; cause?: string } {
  if (!(error instanceof Error)) return { name: "UnknownError", message: String(error) };
  const cause = error.cause instanceof Error ? `${error.cause.name}: ${error.cause.message}` : error.cause ? String(error.cause) : undefined;
  return { name: error.name, message: error.message, ...(cause ? { cause } : {}) };
}

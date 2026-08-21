import { getTurso } from "../turso";
import { GDELTProvider } from "./providers/gdelt";
import { OpenAIWebSearchProvider } from "./providers/openai-web-search";
import { upsertNewsCandidate } from "./repository";

type TopicRow = { id: string; query: string };
const NEWS_POOL_COOLDOWN_MS = 15 * 60 * 1_000;

export type NewsRefreshOptions = {
  language?: "japanese" | "english";
  sourceCountry?: string;
  topicIDs?: string[];
  excludeTopicIDs?: string[];
};

/** GDELT first; one OpenAI request only when GDELT cannot fill five items. */
export async function refreshSharedNewsPool(options: NewsRefreshOptions = {}): Promise<{ topics: number; fetched: number; stored: number; failures: string[] }> {
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
  const latest = (await getTurso().get(
    `SELECT MAX(fetched_at) AS fetchedAt FROM news_articles
     WHERE provider = ? AND LOWER(language) = LOWER(?)
       AND ((LOWER(country) = LOWER(?) AND ? IS NOT NULL) OR (country IS NULL AND ? IS NULL))`,
    "gdelt", language, options.sourceCountry ?? null,
    options.sourceCountry ?? null, options.sourceCountry ?? null,
  )) as { fetchedAt?: string | null } | null;
  const latestFetchedAt = latest?.fetchedAt ? new Date(latest.fetchedAt).getTime() : 0;
  if (latestFetchedAt > 0 && Date.now() - latestFetchedAt < NEWS_POOL_COOLDOWN_MS) {
    console.info("[daily-news] shared pool refresh skipped", {
      reason: "cooldown", provider: "gdelt", topics: topics.length,
      lastFetchedAt: latest?.fetchedAt, cooldownMinutes: NEWS_POOL_COOLDOWN_MS / 60_000,
    });
    return { topics: topics.length, fetched: 0, stored: 0, failures: [] };
  }

  const gdelt = new GDELTProvider();
  let fetched = 0;
  let stored = 0;
  const failures: string[] = [];
  console.info("[daily-news] shared pool refresh started", {
    provider: "gdelt", fallbackProvider: "openai-web-search", topics: topics.length,
    language, sourceCountry: options.sourceCountry ?? null,
  });

  let gdeltCircuitOpen = false;
  for (const topic of topics) {
    if (gdeltCircuitOpen) {
      failures.push(`${topic.id}:gdelt:provider_circuit_open`);
      continue;
    }
    try {
      const candidates = await gdelt.search({
        topicID: topic.id, query: topic.query, language,
        sourceCountry: options.sourceCountry, limit: 5,
      });
      fetched += candidates.length;
      stored += await storeCandidates(topic.id, "gdelt", candidates, failures);
      console.info("[daily-news] gdelt topic refreshed", { topicID: topic.id, fetched: candidates.length });
    } catch (error) {
      const details = errorDetails(error);
      failures.push(`${topic.id}:gdelt:${details.message}`);
      console.warn("[daily-news] gdelt topic refresh failed", { topicID: topic.id, ...details });
      if (details.name === "TimeoutError" || details.name === "AbortError" || details.message === "fetch failed" || details.message.includes("_429")) {
        gdeltCircuitOpen = true;
        console.warn("[daily-news] gdelt circuit opened", {
          reason: details.name === "TimeoutError" || details.name === "AbortError" ? "timeout" : details.message,
          skippedTopics: topics.length - topics.indexOf(topic) - 1,
        });
      }
    }
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
      console.info("[daily-news] openai fallback refreshed", { fetched: candidates.length, stored, reason: "gdelt_underfilled" });
    } catch (error) {
      const details = errorDetails(error);
      failures.push(`openai-fallback:${details.message}`);
      console.warn("[daily-news] openai fallback failed", details);
    }
  }

  const result = { topics: topics.length, fetched, stored, failures: failures.slice(0, 50) };
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

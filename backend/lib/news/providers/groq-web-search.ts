import type { NewsCandidate, NewsProvider, NewsSearchInput } from "../types";

const endpoint = "https://api.groq.com/openai/v1/chat/completions";
const DEFAULT_MODEL = "groq/compound-mini";
const DEFAULT_TIMEOUT_MS = 45_000;
const DEFAULT_PER_TOPIC_LIMIT = 12;
const DEFAULT_TOTAL_LIMIT = 60;

type GroqArticle = {
  topicID?: string;
  url?: string;
  title?: string;
  description?: string;
  publishedAt?: string;
};

type GroqChatCompletion = {
  id?: string;
  choices?: Array<{
    message?: {
      content?: string | null;
    };
  }>;
};

type GroqErrorMetadata = {
  errorCode?: string;
  errorType?: string;
  errorMessage?: string;
  retryAfterMs?: number;
  requestID?: string;
  rateLimitRemainingRequests?: string;
  rateLimitResetRequests?: string;
};

export class GroqWebSearchProvider implements NewsProvider {
  readonly name = "groq-web-search";

  async search(input: NewsSearchInput): Promise<NewsCandidate[]> {
    return this.searchTopics([input]);
  }

  async searchTopics(inputs: NewsSearchInput[]): Promise<NewsCandidate[]> {
    const apiKey = requiredEnvironmentVariable("GROQ_API_KEY");
    const totalLimit = totalLimitFor(inputs);
    const articles: NewsCandidate[] = [];
    const seen = new Set<string>();
    let firstError: unknown;

    for (const input of inputs) {
      if (articles.length >= totalLimit) break;
      const topicLimit = Math.min(limitFor(input), totalLimit - articles.length);
      try {
        const payload = await requestGroqArticles(apiKey, input, topicLimit);
        for (const candidate of parseArticles(payload, input, topicLimit)) {
          if (articles.length >= totalLimit) break;
          const key = canonicalArticleKey(candidate);
          if (seen.has(key)) continue;
          seen.add(key);
          articles.push(candidate);
        }
      } catch (error) {
        console.warn("[daily-news] groq topic search failed", {
          topicID: input.topicID,
          ...errorDetails(error),
        });
        if (!firstError) firstError = error;
      }
    }

    if (articles.length === 0 && firstError) throw firstError;
    return articles;
  }
}

async function requestGroqArticles(
  apiKey: string,
  input: NewsSearchInput,
  limit: number,
): Promise<GroqChatCompletion> {
  let response: Response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      signal: AbortSignal.timeout(timeoutMilliseconds()),
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(requestBody(input, limit)),
    });
  } catch (error) {
    throw networkRequestError(error);
  }

  if (!response.ok) {
    throw new GroqNewsRequestError(response.status, await readGroqErrorMetadata(response));
  }

  return await response.json() as GroqChatCompletion;
}

function requestBody(input: NewsSearchInput, limit: number): Record<string, unknown> {
  const country = searchCountry(input.sourceCountry);
  const body: Record<string, unknown> = {
    model: process.env.GROQ_NEWS_MODEL?.trim() || DEFAULT_MODEL,
    messages: [
      {
        role: "user",
        content: buildPrompt(input, limit),
      },
    ],
    search_settings: {
      exclude_domains: ["wikipedia.org", "youtube.com", "x.com", "twitter.com", "facebook.com", "instagram.com"],
      ...(country ? { country } : {}),
    },
  };
  return body;
}

function buildPrompt(input: NewsSearchInput, limit: number): string {
  const language = input.language === "english" ? "English" : "Japanese";
  const country = input.sourceCountry ? `Country/region focus: ${input.sourceCountry}.` : "Country/region focus: worldwide.";
  return [
    "You collect current news article URLs for a recommendation engine. Use web search.",
    `Find up to ${limit} important news article URLs for this topic: ${input.query}.`,
    `Target output language metadata: ${language}. ${country}`,
    "Prefer articles published today or within the last 48 hours. Include international coverage when relevant.",
    "Prefer original publisher article URLs over aggregators, homepages, search pages, videos, social posts, or liveblog index pages.",
    "If fewer suitable articles exist, return fewer articles rather than inventing URLs.",
    "Return ONLY raw JSON. Do not include markdown, citations outside the JSON, or explanatory prose. The JSON shape must be exactly:",
    `{"articles":[{"topicID":"${jsonStringValue(input.topicID)}","url":"https://publisher.example/article","title":"Article title","description":"One sentence summary","publishedAt":"2026-08-22T00:00:00Z"}]}`,
    "Rules: topicID must be the supplied topicID. url must be a working http/https article URL. publishedAt must be ISO-8601 when available; otherwise use today's date.",
  ].join("\n");
}

function parseArticles(payload: GroqChatCompletion, input: NewsSearchInput, limit: number): NewsCandidate[] {
  const outputText = payload.choices?.[0]?.message?.content?.trim();
  if (!outputText) throw new Error("GROQ_NEWS_EMPTY_OUTPUT");

  let parsed: { articles?: GroqArticle[] };
  try {
    parsed = JSON.parse(outputText) as { articles?: GroqArticle[] };
  } catch {
    throw new Error("GROQ_NEWS_INVALID_OUTPUT");
  }

  return (parsed.articles ?? []).slice(0, limit).flatMap((article) => {
    if (!article.url || !article.title) return [];
    try {
      const url = new URL(article.url);
      if (!/^https?:$/u.test(url.protocol)) return [];
      return [{
        url: url.toString(),
        title: article.title.trim(),
        description: article.description?.trim() || undefined,
        sourceDomain: url.hostname.toLowerCase(),
        language: input.language === "english" ? "English" : "Japanese",
        country: input.sourceCountry,
        publishedAt: parsePublishedAt(article.publishedAt),
        providerID: payload.id,
        topicID: input.topicID,
      } satisfies NewsCandidate];
    } catch {
      return [];
    }
  });
}

function limitFor(input: NewsSearchInput): number {
  const requested = input.limit ?? Number(process.env.GROQ_NEWS_PER_TOPIC_LIMIT);
  if (!Number.isFinite(requested)) return DEFAULT_PER_TOPIC_LIMIT;
  return Math.min(Math.max(Math.round(requested), 1), 20);
}

function totalLimitFor(inputs: NewsSearchInput[]): number {
  const requested = Number(process.env.GROQ_NEWS_TOTAL_LIMIT);
  const defaultLimit = Math.min(inputs.length * DEFAULT_PER_TOPIC_LIMIT, DEFAULT_TOTAL_LIMIT);
  if (!Number.isFinite(requested)) return defaultLimit;
  return Math.min(Math.max(Math.round(requested), 5), 80);
}

function timeoutMilliseconds(): number {
  const requested = Number(process.env.GROQ_NEWS_REQUEST_TIMEOUT_MS);
  if (!Number.isFinite(requested)) return DEFAULT_TIMEOUT_MS;
  return Math.min(Math.max(Math.round(requested), 10_000), 90_000);
}

function parsePublishedAt(value?: string): string {
  if (value) {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.valueOf())) return parsed.toISOString();
  }
  return new Date().toISOString();
}

function canonicalArticleKey(article: NewsCandidate): string {
  try {
    const url = new URL(article.url);
    url.hash = "";
    for (const key of [...url.searchParams.keys()]) {
      if (/^(utm_|fbclid$|gclid$|yclid$|igshid$)/iu.test(key)) {
        url.searchParams.delete(key);
      }
    }
    return url.toString().toLowerCase();
  } catch {
    return article.url.trim().toLowerCase();
  }
}

function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

async function readGroqErrorMetadata(response: Response): Promise<GroqErrorMetadata> {
  let errorCode: string | undefined;
  let errorType: string | undefined;
  let errorMessage: string | undefined;
  try {
    const payload = await response.json() as { error?: { code?: unknown; type?: unknown; message?: unknown } };
    errorCode = safeErrorValue(payload.error?.code);
    errorType = safeErrorValue(payload.error?.type);
    errorMessage = safeErrorValue(payload.error?.message);
  } catch {
    // Status and safe response headers still provide useful diagnostics.
  }
  return {
    errorCode,
    errorType,
    errorMessage,
    retryAfterMs: retryAfterMilliseconds(response),
    requestID: safeErrorValue(response.headers.get("x-request-id")),
    rateLimitRemainingRequests: safeErrorValue(response.headers.get("x-ratelimit-remaining-requests")),
    rateLimitResetRequests: safeErrorValue(response.headers.get("x-ratelimit-reset-requests")),
  };
}

class GroqNewsRequestError extends Error {
  readonly status: number;
  readonly errorCode?: string;
  readonly errorType?: string;
  readonly retryAfterMs?: number;
  readonly requestID?: string;

  constructor(status: number, metadata: GroqErrorMetadata) {
    const details = [
      `GROQ_NEWS_REQUEST_FAILED_${status}`,
      ...(metadata.errorCode ? [`CODE_${metadata.errorCode}`] : []),
      ...(metadata.errorType ? [`TYPE_${metadata.errorType}`] : []),
      ...(metadata.errorMessage ? [`MESSAGE_${metadata.errorMessage}`] : []),
      ...(metadata.retryAfterMs === undefined ? [] : [`RETRY_AFTER_MS_${metadata.retryAfterMs}`]),
      ...(metadata.requestID ? [`REQUEST_ID_${metadata.requestID}`] : []),
      ...(metadata.rateLimitRemainingRequests ? [`REMAINING_REQUESTS_${metadata.rateLimitRemainingRequests}`] : []),
      ...(metadata.rateLimitResetRequests ? [`RESET_REQUESTS_${metadata.rateLimitResetRequests}`] : []),
    ];
    super(details.join("_"));
    this.name = "GroqNewsRequestError";
    this.status = status;
    this.errorCode = metadata.errorCode;
    this.errorType = metadata.errorType;
    this.retryAfterMs = metadata.retryAfterMs;
    this.requestID = metadata.requestID;
  }
}

function retryAfterMilliseconds(response: Response): number | undefined {
  const value = response.headers.get("retry-after")?.trim();
  if (!value) return undefined;
  const seconds = Number(value);
  if (Number.isFinite(seconds) && seconds >= 0) {
    return Math.min(Math.round(seconds * 1_000), 24 * 60 * 60 * 1_000);
  }
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) return undefined;
  return Math.min(Math.max(0, timestamp - Date.now()), 24 * 60 * 60 * 1_000);
}

function safeErrorValue(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const sanitized = value.trim().replace(/[^A-Za-z0-9_-]/gu, "_").replace(/_+/gu, "_").slice(0, 80);
  return sanitized || undefined;
}

function networkRequestError(error: unknown): Error {
  const timeout = error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError");
  const result = new Error(timeout ? "GROQ_NEWS_REQUEST_TIMEOUT" : "GROQ_NEWS_REQUEST_NETWORK_ERROR");
  result.name = timeout && error instanceof Error ? error.name : "GroqNewsNetworkError";
  return result;
}

function errorDetails(error: unknown): { name: string; message: string } {
  if (!(error instanceof Error)) return { name: "UnknownError", message: String(error) };
  return { name: error.name, message: error.message };
}

function jsonStringValue(value: string): string {
  return value.replace(/\\/gu, "\\\\").replace(/"/gu, "\\\"");
}

function searchCountry(sourceCountry?: string): string | undefined {
  const normalized = sourceCountry?.trim().toLowerCase().replace(/[_-]+/gu, " ");
  const compact = normalized?.replace(/[^a-z]/gu, "");
  if (!normalized) return undefined;
  switch (compact) {
    case "jp":
    case "japan":
      return "japan";
    case "us":
    case "usa":
    case "unitedstates":
    case "unitedstatesofamerica":
      return "united states";
    case "uk":
    case "gb":
    case "greatbritain":
    case "unitedkingdom":
      return "united kingdom";
    default:
      return normalized;
  }
}

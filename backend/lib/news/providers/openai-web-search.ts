import type { NewsCandidate, NewsProvider, NewsSearchInput } from "../types";
import { buildMultiTopicNewsWebSearchPrompt, buildNewsWebSearchPrompt } from "../../cast/prompt";

const model = "gpt-5.6-luna";
const endpoint = "https://api.openai.com/v1/responses";
const MAX_ATTEMPTS = 2;
const MAX_TOTAL_RETRY_DELAY_MS = 10_000;
const DEFAULT_RETRY_DELAY_MS = 1_000;
const MAX_RETRY_JITTER_MS = 250;

type SearchArticle = {
  topicID?: string;
  url?: string;
  title?: string;
  description?: string;
  publishedAt?: string;
};

type OpenAIResponse = {
  id?: string;
  output?: Array<{
    type?: string;
    content?: Array<{ type?: string; text?: string }>;
  }>;
};

export class OpenAIWebSearchProvider implements NewsProvider {
  readonly name = "openai-web-search";

  async search(input: NewsSearchInput): Promise<NewsCandidate[]> {
    const apiKey = requiredEnvironmentVariable("OPENAI_API_KEY");
    const limit = Math.min(Math.max(input.limit ?? 10, 1), 10);
    const countryCode = countryCodeFor(input.sourceCountry);
    const prompt = buildNewsWebSearchPrompt(
      input.language ?? "japanese",
      input.query,
      input.sourceCountry,
      limit,
    );

    const response = await fetchWithRetry(apiKey, requestBody(prompt, countryCode, false, 1));

    const payload = await response.json() as OpenAIResponse;
    const outputText = payload.output
      ?.filter((item) => item.type === "message")
      .flatMap((item) => item.content ?? [])
      .filter((content) => content.type === "output_text")
      .map((content) => content.text ?? "")
      .join("\n")
      .trim();
    if (!outputText) throw new Error("OPENAI_NEWS_EMPTY_OUTPUT");

    let parsed: { articles?: SearchArticle[] };
    try {
      parsed = JSON.parse(outputText) as { articles?: SearchArticle[] };
    } catch {
      throw new Error("OPENAI_NEWS_INVALID_OUTPUT");
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

  async searchTopics(inputs: NewsSearchInput[]): Promise<NewsCandidate[]> {
    const first = inputs[0];
    if (!first) return [];
    const apiKey = requiredEnvironmentVariable("OPENAI_API_KEY");
    const limit = Math.min(Math.max(inputs.reduce((total, input) => total + (input.limit ?? 5), 0), 1), 5);
    const validTopicIDs = new Set(inputs.map((input) => input.topicID));
    const articles: NewsCandidate[] = [];
    const prompt = buildMultiTopicNewsWebSearchPrompt(
      first.language ?? "japanese",
      inputs.map((input) => ({ id: input.topicID, query: input.query })),
      first.sourceCountry,
      limit,
    );
    let firstError: unknown;
    try {
      const response = await fetchWithRetry(
        apiKey,
        requestBody(
          prompt,
          countryCodeFor(first.sourceCountry),
          true,
          Math.min(Math.max(inputs.length, 1), 3),
        ),
      );
      const payload = await response.json() as OpenAIResponse;
      addUniqueArticles(articles, parseArticles(payload, first, limit, validTopicIDs), limit);
    } catch (error) {
      firstError = error;
    }

    for (const input of inputs) {
      if (articles.length >= limit) break;
      const topicHasArticle = articles.some((article) => article.topicID === input.topicID);
      const topicLimit = Math.min(Math.max(limit - articles.length, topicHasArticle ? 1 : 2), 5);
      try {
        const response = await fetchWithRetry(
          apiKey,
          requestBody(
            buildNewsWebSearchPrompt(input.language ?? first.language ?? "japanese", input.query, input.sourceCountry ?? first.sourceCountry, topicLimit),
            countryCodeFor(input.sourceCountry ?? first.sourceCountry),
            false,
            1,
          ),
        );
        const payload = await response.json() as OpenAIResponse;
        addUniqueArticles(articles, parseArticles(payload, input, topicLimit), limit);
      } catch (error) {
        if (articles.length === 0 && !firstError) firstError = error;
        console.warn("[daily-news] openai topic fallback failed", {
          topicID: input.topicID,
          ...errorDetails(error),
        });
      }
    }

    if (articles.length > 0) return articles;
    if (firstError) throw firstError;
    return [];
  }
}

function requestBody(
  prompt: string,
  countryCode: string | undefined,
  includeTopicID: boolean,
  maxToolCalls: number,
): string {
  const properties: Record<string, unknown> = {
    url: { type: "string" }, title: { type: "string" }, description: { type: "string" }, publishedAt: { type: "string" },
  };
  const required = ["url", "title", "description", "publishedAt"];
  if (includeTopicID) {
    properties.topicID = { type: "string" };
    required.unshift("topicID");
  }
  return JSON.stringify({
    model,
    input: prompt,
    tools: [{ type: "web_search", search_context_size: "low", ...(countryCode ? { user_location: { type: "approximate", country: countryCode } } : {}) }],
    text: { format: { type: "json_schema", name: "news_articles", strict: true, schema: {
      type: "object", properties: { articles: { type: "array", items: { type: "object", properties, required, additionalProperties: false } } },
      required: ["articles"], additionalProperties: false,
    } } },
    max_output_tokens: 2_000,
    max_tool_calls: maxToolCalls,
    store: false,
  });
}

function parseArticles(
  payload: OpenAIResponse,
  input: NewsSearchInput,
  limit: number,
  validTopicIDs?: Set<string>,
): NewsCandidate[] {
  const outputText = payload.output?.filter((item) => item.type === "message").flatMap((item) => item.content ?? [])
    .filter((content) => content.type === "output_text").map((content) => content.text ?? "").join("\n").trim();
  if (!outputText) throw new Error("OPENAI_NEWS_EMPTY_OUTPUT");
  let parsed: { articles?: SearchArticle[] };
  try { parsed = JSON.parse(outputText) as { articles?: SearchArticle[] }; }
  catch { throw new Error("OPENAI_NEWS_INVALID_OUTPUT"); }
  return (parsed.articles ?? []).slice(0, limit).flatMap((article) => {
    if (!article.url || !article.title) return [];
    try {
      const url = new URL(article.url);
      if (!/^https?:$/u.test(url.protocol)) return [];
      return [{ url: url.toString(), title: article.title.trim(), description: article.description?.trim() || undefined,
        sourceDomain: url.hostname.toLowerCase(), language: input.language === "english" ? "English" : "Japanese",
        country: input.sourceCountry, publishedAt: parsePublishedAt(article.publishedAt), providerID: payload.id,
        topicID: validTopicIDs?.has(article.topicID ?? "") ? article.topicID : input.topicID } satisfies NewsCandidate];
    } catch { return []; }
  });
}

function addUniqueArticles(target: NewsCandidate[], candidates: NewsCandidate[], limit: number): void {
  const seen = new Set(target.map((article) => canonicalArticleKey(article)));
  for (const candidate of candidates) {
    if (target.length >= limit) break;
    const key = canonicalArticleKey(candidate);
    if (seen.has(key)) continue;
    seen.add(key);
    target.push(candidate);
  }
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

function errorDetails(error: unknown): { name: string; message: string } {
  if (!(error instanceof Error)) return { name: "UnknownError", message: String(error) };
  return { name: error.name, message: error.message };
}

function parsePublishedAt(value?: string): string {
  if (value) {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.valueOf())) return parsed.toISOString();
  }
  return new Date().toISOString();
}

function countryCodeFor(sourceCountry?: string): string | undefined {
  switch (sourceCountry?.toLowerCase()) {
    case "japan": return "JP";
    case "unitedstates":
    case "unitedstatesofamerica": return "US";
    case "unitedkingdom": return "GB";
    case "canada": return "CA";
    case "australia": return "AU";
    default: return undefined;
  }
}

function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

async function fetchWithRetry(apiKey: string, body: string): Promise<Response> {
  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
    let response: Response;
    try {
      response = await fetch(endpoint, {
        method: "POST",
        signal: AbortSignal.timeout(45_000),
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body,
      });
    } catch (error) {
      if (attempt >= MAX_ATTEMPTS) throw networkRequestError(error);
      await wait(retryDelay(attempt) ?? DEFAULT_RETRY_DELAY_MS);
      continue;
    }

    if (response.ok) return response;

    const metadata = await readOpenAIErrorMetadata(response);
    const error = new OpenAINewsRequestError(response.status, metadata);
    if (attempt >= MAX_ATTEMPTS || !shouldRetry(response.status, metadata)) {
      throw error;
    }

    const delay = retryDelay(attempt, metadata.retryAfterMs);
    // Retry-After is a minimum. If it does not fit this request's bounded
    // retry budget, fail now and let a later scheduled refresh try again.
    if (delay === undefined) throw error;
    await wait(delay);
  }
  throw new Error("OPENAI_NEWS_REQUEST_FAILED");
}

type OpenAIErrorMetadata = {
  errorCode?: string;
  errorType?: string;
  retryAfterMs?: number;
  requestID?: string;
};

class OpenAINewsRequestError extends Error {
  readonly status: number;
  readonly errorCode?: string;
  readonly errorType?: string;
  readonly retryAfterMs?: number;
  readonly requestID?: string;

  constructor(status: number, metadata: OpenAIErrorMetadata) {
    const details = [
      `OPENAI_NEWS_REQUEST_FAILED_${status}`,
      ...(metadata.errorCode ? [`CODE_${metadata.errorCode}`] : []),
      ...(metadata.errorType ? [`TYPE_${metadata.errorType}`] : []),
      ...(metadata.retryAfterMs === undefined ? [] : [`RETRY_AFTER_MS_${metadata.retryAfterMs}`]),
      ...(metadata.requestID ? [`REQUEST_ID_${metadata.requestID}`] : []),
    ];
    super(details.join("_"));
    this.name = "OpenAINewsRequestError";
    this.status = status;
    this.errorCode = metadata.errorCode;
    this.errorType = metadata.errorType;
    this.retryAfterMs = metadata.retryAfterMs;
    this.requestID = metadata.requestID;
  }
}

async function readOpenAIErrorMetadata(response: Response): Promise<OpenAIErrorMetadata> {
  let errorCode: string | undefined;
  let errorType: string | undefined;
  try {
    const payload = await response.json() as { error?: { code?: unknown; type?: unknown } };
    errorCode = safeErrorValue(payload.error?.code);
    errorType = safeErrorValue(payload.error?.type);
  } catch {
    // Status and safe response headers still provide useful diagnostics.
  }
  return {
    errorCode,
    errorType,
    retryAfterMs: retryAfterMilliseconds(response),
    requestID: safeErrorValue(response.headers.get("x-request-id")),
  };
}

function shouldRetry(status: number, metadata: OpenAIErrorMetadata): boolean {
  if (status >= 500 || status === 408) return true;
  if (status !== 429 || isQuotaOrBillingError(metadata)) return false;
  const values = [metadata.errorCode, metadata.errorType].filter((value): value is string => Boolean(value));
  return metadata.retryAfterMs !== undefined || values.some((value) => value.toLowerCase().includes("rate_limit"));
}

function isQuotaOrBillingError(metadata: OpenAIErrorMetadata): boolean {
  const values = [metadata.errorCode, metadata.errorType]
    .filter((value): value is string => Boolean(value))
    .map((value) => value.toLowerCase());
  return values.some((value) =>
    value.includes("quota")
    || value.includes("credit")
    || value.includes("spend_limit")
    || value.includes("usage_limit")
    || value.includes("billing"),
  );
}

function retryDelay(attempt: number, retryAfterMs?: number): number | undefined {
  const minimumDelay = retryAfterMs ?? DEFAULT_RETRY_DELAY_MS * (2 ** (attempt - 1));
  if (minimumDelay > MAX_TOTAL_RETRY_DELAY_MS) return undefined;
  const jitterBudget = Math.min(MAX_RETRY_JITTER_MS, MAX_TOTAL_RETRY_DELAY_MS - minimumDelay);
  const jitter = Math.floor(Math.random() * (jitterBudget + 1));
  return minimumDelay + jitter;
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
  const result = new Error(timeout ? "OPENAI_NEWS_REQUEST_TIMEOUT" : "OPENAI_NEWS_REQUEST_NETWORK_ERROR");
  result.name = timeout && error instanceof Error ? error.name : "OpenAINewsNetworkError";
  return result;
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

import type { NewsCandidate, NewsProvider, NewsSearchInput } from "../types";
import { buildMultiTopicNewsWebSearchPrompt, buildNewsWebSearchPrompt } from "../../cast/prompt";

const model = "gpt-5.6-luna";
const endpoint = "https://api.openai.com/v1/responses";

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

    const response = await fetchWithRetry(apiKey, requestBody(prompt, countryCode, false));

    if (!response.ok) {
      throw new Error(`OPENAI_NEWS_REQUEST_FAILED_${response.status}`);
    }

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
    const prompt = buildMultiTopicNewsWebSearchPrompt(
      first.language ?? "japanese",
      inputs.map((input) => ({ id: input.topicID, query: input.query })),
      first.sourceCountry,
      limit,
    );
    const response = await fetchWithRetry(
      apiKey,
      requestBody(prompt, countryCodeFor(first.sourceCountry), true),
    );
    if (!response.ok) throw new Error(`OPENAI_NEWS_REQUEST_FAILED_${response.status}`);
    const payload = await response.json() as OpenAIResponse;
    return parseArticles(payload, first, limit, new Set(inputs.map((input) => input.topicID)));
  }
}

function requestBody(prompt: string, countryCode: string | undefined, includeTopicID: boolean): string {
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
  let response: Response | undefined;
  // A second attempt is enough for transient 429/5xx responses. More retries
  // multiply Web Search charges when a provider is already rate-limited.
  for (let attempt = 1; attempt <= 2; attempt += 1) {
    response = await fetch(endpoint, {
      method: "POST",
      signal: AbortSignal.timeout(45_000),
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body,
    });
    // 429 means the account/provider rate limit was reached. Retrying here
    // only creates another billable request and can prolong the lockout.
    if (response.ok || response.status === 429 || response.status < 500) return response;
    if (attempt < 2) await wait(retryDelay(attempt, response));
  }
  return response!;
}

function retryDelay(attempt: number, response: Response): number {
  const retryAfter = Number(response.headers.get("retry-after"));
  if (Number.isFinite(retryAfter) && retryAfter > 0) {
    return Math.min(retryAfter * 1_000, 30_000);
  }
  return 3_000 * (2 ** (attempt - 1));
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

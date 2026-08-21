import type { NewsCandidate, NewsProvider, NewsSearchInput } from "../types";

const endpoint = "https://api.gdeltproject.org/api/v2/doc/doc";
const MIN_REQUEST_INTERVAL_MS = 5_500;
const DEFAULT_REQUEST_TIMEOUT_MS = 3_000;
const DEFAULT_FAILURE_COOLDOWN_MS = 15 * 60 * 1_000;
const MAX_ATTEMPTS = 2;
const MAX_RETRY_DELAY_MS = 15_000;

// Keep every request in this Node process behind one serialized 5.5-second gate
// so concurrent searches cannot burst against GDELT's public endpoint.
let lastRequestStartedAt = 0;
let requestGate: Promise<void> = Promise.resolve();
let unavailableUntil = 0;

type GDELTArticle = {
  url?: string;
  title?: string;
  seendate?: string;
  socialimage?: string;
  domain?: string;
  language?: string;
  sourcecountry?: string;
};

export class GDELTProvider implements NewsProvider {
  readonly name = "gdelt";

  async search(input: NewsSearchInput): Promise<NewsCandidate[]> {
    if (Date.now() < unavailableUntil) {
      throw new Error("GDELT_PROVIDER_TEMPORARILY_UNAVAILABLE");
    }
    const url = new URL(endpoint);
    const language = input.language === "english" ? "english" : "japanese";
    const country = input.sourceCountry ? ` sourcecountry:${input.sourceCountry}` : "";
    url.searchParams.set("query", `${compactQuery(input.query)} sourcelang:${language}${country}`);
    url.searchParams.set("mode", "artlist");
    url.searchParams.set("format", "json");
    url.searchParams.set("maxrecords", String(Math.min(Math.max(input.limit ?? 30, 1), 250)));
    url.searchParams.set("timespan", process.env.GDELT_TIMESPAN?.trim() || "1d");
    url.searchParams.set("sort", "datedesc");

    let response: Response | undefined;
    let lastError: unknown;
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      await waitForRequestSlot();
      response = undefined;
      try {
        response = await fetch(url, {
          headers: { "User-Agent": "StackCast/1.0 personal-news" },
          signal: AbortSignal.timeout(requestTimeoutMilliseconds()),
          cache: "no-store",
        });
      } catch (error) {
        lastError = error;
        // A connection timeout means the upstream is currently unreachable.
        // Retrying the same request only makes the refresh block longer; the
        // caller will open its fallback/cache path instead.
        if (error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError")) {
          markUnavailable();
          break;
        }
        if (attempt < MAX_ATTEMPTS) {
          await wait(retryDelay(attempt) ?? MIN_REQUEST_INTERVAL_MS);
          continue;
        }
        break;
      }

      if (response.ok) break;
      lastError = requestError(response);
      // A 429 needs a later refresh rather than an immediate retry. Other 4xx
      // responses are non-transient and must not be swallowed by this loop.
      if (response.status === 429) {
        markUnavailable(response);
        break;
      }
      if (response.status < 500) break;
      if (attempt < MAX_ATTEMPTS) {
        const delay = retryDelay(attempt, response);
        // Retry-After is a minimum. If it exceeds this request's bounded retry
        // budget, let the next scheduled refresh try again instead.
        if (delay === undefined) break;
        await wait(delay);
      }
    }
    if (!response?.ok) throw lastError instanceof Error ? lastError : new Error("GDELT_REQUEST_FAILED");

    const payload = (await response.json()) as { articles?: GDELTArticle[] };
    return (payload.articles ?? []).flatMap((article) => {
      if (!article.url || !article.title) return [];
      try {
        const parsed = new URL(article.url);
        return [{
          url: article.url,
          title: article.title.trim(),
          imageURL: article.socialimage || undefined,
          sourceDomain: article.domain?.toLowerCase() || parsed.hostname.toLowerCase(),
          language: article.language || (input.language === "english" ? "English" : "Japanese"),
          country: article.sourcecountry || undefined,
          publishedAt: parseGDELTDate(article.seendate),
        } satisfies NewsCandidate];
      } catch {
        return [];
      }
    });
  }
}

function compactQuery(query: string): string {
  const normalized = query.trim();
  const parenthesized = normalized.match(/^\((.*)\)$/u)?.[1] ?? normalized;
  const firstTerm = parenthesized.split(/\s+OR\s+/iu)[0]?.trim();
  return firstTerm || normalized;
}

function requestTimeoutMilliseconds(): number {
  const value = Number(process.env.GDELT_REQUEST_TIMEOUT_MS);
  if (!Number.isFinite(value)) return DEFAULT_REQUEST_TIMEOUT_MS;
  return Math.min(Math.max(Math.round(value), 1_000), 10_000);
}

function failureCooldownMilliseconds(response?: Response): number {
  const retryAfterMs = response ? retryAfterMilliseconds(response) : undefined;
  if (retryAfterMs !== undefined) return Math.min(Math.max(retryAfterMs, 60_000), 60 * 60 * 1_000);
  const value = Number(process.env.GDELT_FAILURE_COOLDOWN_MS);
  if (!Number.isFinite(value)) return DEFAULT_FAILURE_COOLDOWN_MS;
  return Math.min(Math.max(Math.round(value), 0), 60 * 60 * 1_000);
}

function markUnavailable(response?: Response): void {
  const cooldown = failureCooldownMilliseconds(response);
  if (cooldown <= 0) return;
  unavailableUntil = Math.max(unavailableUntil, Date.now() + cooldown);
}

async function waitForRequestSlot(): Promise<void> {
  const previous = requestGate;
  let release!: () => void;
  requestGate = new Promise<void>((resolve) => { release = resolve; });
  await previous;
  const elapsed = Date.now() - lastRequestStartedAt;
  if (elapsed < MIN_REQUEST_INTERVAL_MS) {
    await wait(MIN_REQUEST_INTERVAL_MS - elapsed);
  }
  lastRequestStartedAt = Date.now();
  release();
}

function requestError(response: Response): GDELTRequestError {
  return new GDELTRequestError(
    response.status,
    retryAfterMilliseconds(response),
    safeHeaderValue(response.headers.get("x-request-id")),
  );
}

class GDELTRequestError extends Error {
  readonly status: number;
  readonly retryAfterMs?: number;
  readonly requestID?: string;

  constructor(status: number, retryAfterMs?: number, requestID?: string) {
    const details = [
      `GDELT_REQUEST_FAILED_${status}`,
      ...(retryAfterMs === undefined ? [] : [`RETRY_AFTER_MS_${retryAfterMs}`]),
      ...(requestID ? [`REQUEST_ID_${requestID}`] : []),
    ];
    super(details.join("_"));
    this.name = "GDELTRequestError";
    this.status = status;
    this.retryAfterMs = retryAfterMs;
    this.requestID = requestID;
  }
}

function retryDelay(attempt: number, response?: Response): number | undefined {
  const retryAfterMs = response ? retryAfterMilliseconds(response) : undefined;
  if (retryAfterMs !== undefined) {
    const delay = Math.max(MIN_REQUEST_INTERVAL_MS, retryAfterMs);
    return delay <= MAX_RETRY_DELAY_MS ? delay : undefined;
  }
  return Math.min(MIN_REQUEST_INTERVAL_MS * (2 ** (attempt - 1)), MAX_RETRY_DELAY_MS);
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

function safeHeaderValue(value: string | null): string | undefined {
  const sanitized = value?.trim().replace(/[^A-Za-z0-9_-]/gu, "").slice(0, 80);
  return sanitized || undefined;
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function parseGDELTDate(value?: string): string {
  if (!value) return new Date().toISOString();
  const match = value.match(/^(\d{4})(\d{2})(\d{2})T?(\d{2})(\d{2})(\d{2})Z?$/);
  if (!match) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.valueOf()) ? new Date().toISOString() : parsed.toISOString();
  }
  return new Date(`${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}Z`).toISOString();
}

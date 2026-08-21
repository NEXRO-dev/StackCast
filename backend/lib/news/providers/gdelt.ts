import type { NewsCandidate, NewsProvider, NewsSearchInput } from "../types";

const endpoint = "https://api.gdeltproject.org/api/v2/doc/doc";
const MIN_REQUEST_INTERVAL_MS = 5_500;
const REQUEST_TIMEOUT_MS = 10_000;
const MAX_ATTEMPTS = 3;

// GDELT's public endpoint is shared and rate-limited by source IP. Keep every
// request in this Node process behind one serialized 5.5-second gate.
let lastRequestStartedAt = 0;
let requestGate: Promise<void> = Promise.resolve();

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
    const url = new URL(endpoint);
    const language = input.language === "english" ? "english" : "japanese";
    const country = input.sourceCountry ? ` sourcecountry:${input.sourceCountry}` : "";
    url.searchParams.set("query", `${input.query} sourcelang:${language}${country}`);
    url.searchParams.set("mode", "artlist");
    url.searchParams.set("format", "json");
    url.searchParams.set("maxrecords", String(Math.min(Math.max(input.limit ?? 30, 1), 250)));
    url.searchParams.set("sort", "datedesc");

    let response: Response | undefined;
    let lastError: unknown;
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt += 1) {
      await waitForRequestSlot();
      response = undefined;
        try {
          response = await fetch(url, {
            headers: { "User-Agent": "StackCast/1.0 personal-news" },
            signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
            cache: "no-store",
          });
        if (response.ok) break;
        lastError = new Error(`GDELT_REQUEST_FAILED_${response.status}`);
        if (response.status !== 429 && response.status < 500) throw lastError;
      } catch (error) {
        lastError = error;
        // A connection timeout means the upstream is currently unreachable.
        // Retrying the same request only makes the refresh block longer; the
        // caller will open its fallback/cache path instead.
        if (error instanceof Error && (error.name === "TimeoutError" || error.name === "AbortError")) {
          break;
        }
      }
      // Do not retry rate-limit responses. GDELT is IP-rate-limited and
      // another immediate request only worsens the block.
      if (response?.status === 429) break;
      if (attempt < MAX_ATTEMPTS) {
        await wait(retryDelay(attempt, response));
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

function retryDelay(attempt: number, response?: Response): number {
  const retryAfter = response?.headers.get("retry-after");
  const retryAfterSeconds = retryAfter ? Number(retryAfter) : NaN;
  if (Number.isFinite(retryAfterSeconds) && retryAfterSeconds > 0) {
    return Math.max(MIN_REQUEST_INTERVAL_MS, retryAfterSeconds * 1_000);
  }
  return MIN_REQUEST_INTERVAL_MS * (2 ** (attempt - 1));
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

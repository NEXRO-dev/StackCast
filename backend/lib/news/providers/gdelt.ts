import type { NewsCandidate, NewsProvider, NewsSearchInput } from "../types";

const endpoint = "https://api.gdeltproject.org/api/v2/doc/doc";

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
    url.searchParams.set("query", `${input.query} sourcelang:${input.language === "english" ? "english" : "japanese"}`);
    url.searchParams.set("mode", "artlist");
    url.searchParams.set("format", "json");
    url.searchParams.set("maxrecords", String(Math.min(Math.max(input.limit ?? 30, 1), 250)));
    url.searchParams.set("sort", "datedesc");

    const response = await fetch(url, {
      headers: { "User-Agent": "StackCast/1.0 personal-news" },
      signal: AbortSignal.timeout(20_000),
      cache: "no-store",
    });
    if (!response.ok) throw new Error(`GDELT_REQUEST_FAILED_${response.status}`);

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

function parseGDELTDate(value?: string): string {
  if (!value) return new Date().toISOString();
  const match = value.match(/^(\d{4})(\d{2})(\d{2})T?(\d{2})(\d{2})(\d{2})Z?$/);
  if (!match) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.valueOf()) ? new Date().toISOString() : parsed.toISOString();
  }
  return new Date(`${match[1]}-${match[2]}-${match[3]}T${match[4]}:${match[5]}:${match[6]}Z`).toISOString();
}

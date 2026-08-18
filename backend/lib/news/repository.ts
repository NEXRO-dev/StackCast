import { createHash, randomUUID } from "node:crypto";
import { getTurso } from "../turso";
import { canonicalizeURL } from "./canonical-url";
import type { NewsCandidate } from "./types";

export async function upsertNewsCandidate(
  topicID: string,
  provider: string,
  candidate: NewsCandidate,
): Promise<string> {
  const database = getTurso();
  const canonicalURL = canonicalizeURL(candidate.url);
  const existing = (await database.get(
    "SELECT id FROM news_articles WHERE canonical_url = ? LIMIT 1",
    canonicalURL,
  )) as { id?: string } | null;
  const id = existing?.id ?? randomUUID();
  const now = new Date().toISOString();
  const expiresAt = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();
  const contentHash = createHash("sha256").update(`${candidate.title}\n${canonicalURL}`).digest("hex");

  await database.batch([
    {
      sql: `INSERT INTO news_articles
        (id, canonical_url, original_url, title, description, image_url, source_domain,
         language, country, published_at, provider, provider_id, content_hash, quality_score,
         fetched_at, expires_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0.5, ?, ?)
       ON CONFLICT(canonical_url) DO UPDATE SET
         original_url = excluded.original_url, title = excluded.title,
         image_url = COALESCE(excluded.image_url, news_articles.image_url),
         source_domain = excluded.source_domain, language = excluded.language,
         country = excluded.country, published_at = excluded.published_at,
         provider = excluded.provider, content_hash = excluded.content_hash,
         fetched_at = excluded.fetched_at, expires_at = excluded.expires_at`,
      args: [id, canonicalURL, candidate.url, candidate.title, candidate.description ?? null,
        candidate.imageURL ?? null, candidate.sourceDomain, candidate.language, candidate.country ?? null,
        candidate.publishedAt, provider, candidate.providerID ?? null, contentHash, now, expiresAt],
    },
    {
      sql: `INSERT INTO news_article_topics (article_id, topic_id, score, source)
            VALUES (?, ?, 1, ?)
            ON CONFLICT(article_id, topic_id) DO UPDATE SET score = MAX(score, excluded.score), source = excluded.source`,
      args: [id, topicID, provider],
    },
  ], "immediate");
  return id;
}

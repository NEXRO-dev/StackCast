import { randomUUID } from "node:crypto";
import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { featureEnabled } from "@/lib/feature-flags";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

const allowedEvents = new Set(["impression", "open", "dwell", "save", "unsave", "dislike", "mute_topic", "mute_source", "add_to_cast", "cast_created", "cast_completed"]);

export async function POST(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  let events: Array<Record<string, unknown>>;
  try {
    const body = await request.json() as { events?: Array<Record<string, unknown>> };
    events = body.events ?? [];
  } catch {
    return errorResponse("invalid_input", "Events must be valid JSON.", 400);
  }
  if (events.length < 1 || events.length > 50) return errorResponse("invalid_input", "Send between 1 and 50 events.", 400);

  const now = new Date().toISOString();
  const statements = events.flatMap((event) => {
    const type = typeof event.eventType === "string" ? event.eventType : "";
    const articleID = typeof event.articleID === "string" ? event.articleID : "";
    if (!allowedEvents.has(type) || !articleID) return [];
    return [{
      sql: `INSERT OR IGNORE INTO recommendation_events
        (id, user_id, article_id, event_type, surface, session_id, dwell_ms, position, metadata_json, occurred_at, received_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      args: [typeof event.id === "string" ? event.id : randomUUID(), userID, articleID, type,
        typeof event.surface === "string" ? event.surface : "home",
        typeof event.sessionID === "string" ? event.sessionID : null,
        typeof event.dwellMS === "number" ? Math.max(0, Math.round(event.dwellMS)) : null,
        typeof event.position === "number" ? Math.round(event.position) : null,
        event.metadata ? JSON.stringify(event.metadata).slice(0, 4000) : null,
        typeof event.occurredAt === "string" ? event.occurredAt : now, now],
    }];
  });
  if (statements.length === 0) return errorResponse("invalid_input", "No valid events were supplied.", 400);
  await getTurso().batch(statements, "immediate");
  if (featureEnabled("RECOMMENDATION_MEMORY_ENABLED")) {
    await aggregateMemory(userID, statements.length, now);
  }
  return Response.json({ accepted: statements.length });
}

async function aggregateMemory(userID: string, _: number, now: string) {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
  const rows = await getTurso().all(
    `SELECT t.topic_id AS topicID,
            SUM(CASE e.event_type
              WHEN 'save' THEN 1.5 WHEN 'add_to_cast' THEN 2.0 WHEN 'cast_completed' THEN 2.5
              WHEN 'dwell' THEN 0.6 WHEN 'open' THEN 0.2 WHEN 'dislike' THEN -3.0 ELSE 0 END) AS score
     FROM recommendation_events e
     JOIN news_article_topics t ON t.article_id = e.article_id
     WHERE e.user_id = ? AND e.occurred_at > ?
     GROUP BY t.topic_id`,
    userID, thirtyDaysAgo,
  ) as Array<{ topicID: string; score: number }>;
  for (const row of rows) {
    const weight = Math.min(1, Math.abs(Number(row.score) || 0) / 5);
    if (weight === 0) continue;
    await getTurso().run(
      `INSERT INTO user_memory_items
        (id, user_id, kind, value, polarity, weight, origin, reason, last_event_at, expires_at, created_at, updated_at)
       VALUES (?, ?, 'topic', ?, ?, ?, 'behavior', ?, ?, datetime(?, '+180 days'), ?, ?)
       ON CONFLICT(user_id, kind, value) DO UPDATE SET
         polarity = excluded.polarity, weight = excluded.weight, reason = excluded.reason,
         last_event_at = excluded.last_event_at, expires_at = excluded.expires_at, updated_at = excluded.updated_at`,
      randomUUID(), userID, row.topicID, row.score >= 0 ? "positive" : "negative", weight,
      row.score >= 0 ? "最近の閲覧・保存行動から" : "興味なしの指定から", now, now, now, now,
    );
  }
}

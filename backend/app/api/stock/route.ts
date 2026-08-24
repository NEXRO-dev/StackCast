import { randomUUID } from "node:crypto";
import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type StockItem = {
  id?: string;
  url?: string;
  title?: string;
  source?: string;
  savedAt?: string;
  state?: "unread" | "inProgress" | "completed";
  completedAt?: string | null;
  updatedAt?: string;
};

async function currentItems(userID: string) {
  return getTurso().all(
    `SELECT id, canonical_url AS url, title, source, saved_at AS savedAt,
            state, completed_at AS completedAt, updated_at AS updatedAt
     FROM saved_articles WHERE user_id = ? ORDER BY saved_at DESC`,
    userID,
  );
}

export async function GET(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  return Response.json({ items: await currentItems(userID) });
}

export async function PUT(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  let body: { items?: StockItem[] };
  try {
    body = await request.json() as { items?: StockItem[] };
  } catch {
    return errorResponse("invalid_input", "Items must be valid JSON.", 400);
  }

  const now = new Date().toISOString();
  const items = Array.isArray(body.items) ? body.items.slice(0, 200) : [];
  const seenURLs = new Set<string>();
  const uniqueItems = items.flatMap((item) => {
    if (typeof item.url !== "string" || item.url.trim().length === 0) return [];
    const url = item.url.trim();
    if (seenURLs.has(url)) return [];
    seenURLs.add(url);
    return [{ ...item, url }];
  });
  const usedIDs = new Set<string>();
  const statements = uniqueItems.map((item) => {
    const state = item.state === "completed" || item.state === "inProgress" ? item.state : "unread";
    const savedAt = typeof item.savedAt === "string" ? item.savedAt : now;
    const updatedAt = typeof item.updatedAt === "string" ? item.updatedAt : now;
    const requestedID = typeof item.id === "string" && item.id ? item.id : null;
    const id = requestedID && !usedIDs.has(requestedID) ? requestedID : randomUUID();
    usedIDs.add(id);
    return {
      sql: `INSERT INTO saved_articles
        (id, user_id, canonical_url, title, source, saved_at, state, completed_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(user_id, canonical_url) DO UPDATE SET
         id = excluded.id, title = excluded.title, source = excluded.source,
         saved_at = excluded.saved_at, state = excluded.state,
         completed_at = excluded.completed_at, updated_at = excluded.updated_at`,
      args: [
        id,
        userID,
        item.url,
        typeof item.title === "string" && item.title ? item.title : item.url,
        typeof item.source === "string" ? item.source : "",
        savedAt,
        state,
        state === "completed" ? (item.completedAt ?? now) : null,
        updatedAt,
      ],
    };
  });

  await getTurso().batch([
    { sql: "DELETE FROM saved_articles WHERE user_id = ?", args: [userID] },
    ...statements,
  ], "immediate");
  return Response.json({ items: await currentItems(userID) });
}

export async function DELETE(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  let body: { id?: string; url?: string } = {};
  try { body = await request.json() as typeof body; } catch { /* empty body means all */ }
  if (body.id) {
    await getTurso().run("DELETE FROM saved_articles WHERE user_id = ? AND id = ?", userID, body.id);
  } else if (body.url) {
    await getTurso().run("DELETE FROM saved_articles WHERE user_id = ? AND canonical_url = ?", userID, body.url);
  } else {
    await getTurso().run("DELETE FROM saved_articles WHERE user_id = ?", userID);
  }
  return Response.json({ success: true });
}

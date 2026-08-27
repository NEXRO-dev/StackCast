import { randomUUID } from "node:crypto";
import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { effectiveSubscriptionForUser } from "@/lib/billing/effective-plan";
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

type SavedArticleOwnerRow = {
  id: string;
  userID: string;
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
  const subscription = await effectiveSubscriptionForUser(getTurso(), userID);
  const maxSavedURLs = subscription.effectivePlanTier === "plus" ? 100 : 200;
  const items = Array.isArray(body.items) ? body.items.slice(0, maxSavedURLs) : [];
  const seenURLs = new Set<string>();
  const uniqueItems = items.flatMap((item) => {
    if (typeof item.url !== "string" || item.url.trim().length === 0) return [];
    const url = item.url.trim();
    if (seenURLs.has(url)) return [];
    seenURLs.add(url);
    return [{ ...item, url }];
  });

  // Article IDs originate in the shared app-group store. When a user signs out
  // and another user signs in, that local snapshot can contain IDs already
  // owned by the previous account. Since `saved_articles.id` is a global
  // primary key, preserve an incoming ID only when it is unused or belongs to
  // the current user.
  const requestedIDs = [...new Set(uniqueItems.flatMap((item) => (
    typeof item.id === "string" && item.id.trim() ? [item.id.trim()] : []
  )))];
  const existingOwners = requestedIDs.length === 0
    ? []
    : await getTurso().all(
      `SELECT id, user_id AS userID
       FROM saved_articles
       WHERE id IN (${requestedIDs.map(() => "?").join(", ")})`,
      ...requestedIDs,
    ) as SavedArticleOwnerRow[];
  const ownerByID = new Map(existingOwners.map((row) => [row.id, row.userID]));
  const usedIDs = new Set<string>();
  const statements = uniqueItems.map((item) => {
    const state = item.state === "completed" || item.state === "inProgress" ? item.state : "unread";
    const savedAt = typeof item.savedAt === "string" ? item.savedAt : now;
    const updatedAt = typeof item.updatedAt === "string" ? item.updatedAt : now;
    const requestedID = typeof item.id === "string" && item.id.trim() ? item.id.trim() : null;
    const requestedIDOwner = requestedID ? ownerByID.get(requestedID) : undefined;
    const canPreserveRequestedID = requestedID
      && !usedIDs.has(requestedID)
      && (!requestedIDOwner || requestedIDOwner === userID);
    const id = canPreserveRequestedID ? requestedID : randomUUID();
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

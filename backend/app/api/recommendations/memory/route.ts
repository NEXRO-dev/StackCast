import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  const items = await getTurso().all(
    `SELECT id, kind, value, polarity, weight, origin, reason,
            last_event_at AS lastEventAt, expires_at AS expiresAt
     FROM user_memory_items WHERE user_id = ? ORDER BY weight DESC, updated_at DESC`,
    userID,
  );
  return Response.json({ items });
}

export async function DELETE(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  await getTurso().batch([
    { sql: "DELETE FROM daily_news_edition_items WHERE edition_id IN (SELECT id FROM daily_news_editions WHERE user_id = ?)", args: [userID] },
    { sql: "DELETE FROM daily_news_editions WHERE user_id = ?", args: [userID] },
    { sql: "DELETE FROM recommendation_events WHERE user_id = ?", args: [userID] },
    { sql: "DELETE FROM user_memory_items WHERE user_id = ?", args: [userID] },
  ], "immediate");
  return Response.json({ success: true });
}

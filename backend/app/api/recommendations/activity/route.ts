import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  const database = getTurso();
  const user = await database.get(
    "SELECT created_at AS createdAt FROM users WHERE id = ? LIMIT 1",
    userID,
  ) as { createdAt: string } | null;

  if (!user) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  const days = await database.all(
    `SELECT activity_day AS date, SUM(activity_count) AS count
     FROM (
       SELECT substr(occurred_at, 1, 10) AS activity_day, COUNT(*) AS activity_count
       FROM recommendation_events
       WHERE user_id = ?
       GROUP BY substr(occurred_at, 1, 10)
       UNION ALL
       SELECT substr(saved_at, 1, 10), COUNT(*)
       FROM saved_articles
       WHERE user_id = ?
       GROUP BY substr(saved_at, 1, 10)
       UNION ALL
       SELECT substr(completed_at, 1, 10), COUNT(*)
       FROM saved_articles
       WHERE user_id = ? AND completed_at IS NOT NULL
       GROUP BY substr(completed_at, 1, 10)
       UNION ALL
       SELECT substr(created_at, 1, 10), COUNT(*)
       FROM casts
       WHERE user_id = ?
       GROUP BY substr(created_at, 1, 10)
       UNION ALL
       SELECT substr(completed_at, 1, 10), COUNT(*)
       FROM casts
       WHERE user_id = ? AND completed_at IS NOT NULL
       GROUP BY substr(completed_at, 1, 10)
     )
     GROUP BY activity_day
     ORDER BY activity_day ASC`,
    userID, userID, userID, userID, userID,
  ) as Array<{ date: string; count: number }>;

  return Response.json({ accountCreatedAt: user.createdAt, days });
}

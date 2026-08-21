import { errorResponse } from "@/lib/auth/response";
import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { getTurso } from "@/lib/turso";
import { effectiveSubscriptionForUser } from "@/lib/billing/effective-plan";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const token = bearerToken(request);

  if (!token) {
    return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  }

  try {
    const database = getTurso();
    const session = (await database.get(
      `SELECT user_id AS userID
       FROM auth_sessions
       WHERE token_hash = ? AND expires_at > ?
       LIMIT 1`,
      hashSessionToken(token),
      new Date().toISOString(),
    )) as { userID?: string } | null;

    if (!session?.userID) {
      return errorResponse("unauthorized", "Session is invalid or expired.", 401);
    }

    const subscription = await effectiveSubscriptionForUser(database, session.userID);

    return Response.json({
      subscription: {
        ...subscription,
        planTier: subscription.effectivePlanTier,
        isActive: subscription.effectiveIsActive,
      },
    });
  } catch (error) {
    console.error("Billing subscription lookup failed", error);
    if (error instanceof TypeError || (error instanceof Error && /fetch failed|timeout|timed out/i.test(error.message))) {
      return errorResponse("database_unavailable", "Database is temporarily unavailable. Please try again.", 503);
    }
    return errorResponse("server_error", "Unable to load billing status.", 500);
  }
}

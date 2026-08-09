import { errorResponse } from "@/lib/auth/response";
import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type SubscriptionRow = {
  planTier: string | null;
  entitlementId: string;
  productId: string | null;
  store: string | null;
  environment: string;
  status: string;
  isActive: number;
  purchasedAt: string | null;
  expiresAt: string | null;
  cancelledAt: string | null;
  updatedAt: string;
};

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

    const subscription = (await database.get(
      `SELECT
         plan_tier AS planTier,
         entitlement_id AS entitlementId,
         product_id AS productId,
         store,
         environment,
         status,
         is_active AS isActive,
         purchased_at AS purchasedAt,
         expires_at AS expiresAt,
         cancelled_at AS cancelledAt,
         updated_at AS updatedAt
       FROM billing_subscriptions
       WHERE user_id = ?
       ORDER BY is_active DESC, updated_at DESC
       LIMIT 1`,
      session.userID,
    )) as SubscriptionRow | null;

    return Response.json({
      subscription: subscription
        ? {
            ...subscription,
            isActive: Boolean(subscription.isActive),
          }
        : null,
    });
  } catch (error) {
    console.error("Billing subscription lookup failed", error);
    return errorResponse("server_error", "Unable to load billing status.", 500);
  }
}

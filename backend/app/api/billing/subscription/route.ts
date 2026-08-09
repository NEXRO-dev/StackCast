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
  source: "revenuecat" | "admin_override";
  overrideExpiresAt: string | null;
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

    const now = new Date().toISOString();
    const subscription = (await database.get(
      `WITH ranked_billing AS (
         SELECT b.*,
                ROW_NUMBER() OVER (
                  PARTITION BY b.user_id
                  ORDER BY b.is_active DESC, b.updated_at DESC
                ) AS row_number
         FROM billing_subscriptions b
       )
       SELECT
         CASE WHEN admin_override.user_id IS NOT NULL
           THEN admin_override.plan_tier ELSE billing.plan_tier END AS planTier,
         COALESCE(billing.entitlement_id, 'admin_override') AS entitlementId,
         billing.product_id AS productId,
         billing.store,
         CASE WHEN admin_override.user_id IS NOT NULL
           THEN 'admin' ELSE billing.environment END AS environment,
         CASE WHEN admin_override.user_id IS NOT NULL
           THEN CASE WHEN admin_override.is_active = 1 THEN 'active' ELSE 'expired' END
           ELSE billing.status END AS status,
         CASE WHEN admin_override.user_id IS NOT NULL
           THEN admin_override.is_active ELSE billing.is_active END AS isActive,
         billing.purchased_at AS purchasedAt,
         CASE WHEN admin_override.user_id IS NOT NULL
           THEN admin_override.expires_at ELSE billing.expires_at END AS expiresAt,
         billing.cancelled_at AS cancelledAt,
         CASE WHEN admin_override.user_id IS NOT NULL
           THEN admin_override.updated_at ELSE billing.updated_at END AS updatedAt,
         CASE WHEN admin_override.user_id IS NOT NULL
           THEN 'admin_override' ELSE 'revenuecat' END AS source,
         admin_override.expires_at AS overrideExpiresAt
       FROM users
       LEFT JOIN ranked_billing billing
         ON billing.user_id = users.id AND billing.row_number = 1
       LEFT JOIN admin_plan_overrides admin_override
         ON admin_override.user_id = users.id
        AND (admin_override.expires_at IS NULL OR admin_override.expires_at > ?)
       WHERE users.id = ?
         AND (billing.user_id IS NOT NULL OR admin_override.user_id IS NOT NULL)
       LIMIT 1`,
      now,
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

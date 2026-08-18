import type { Connection } from "@tursodatabase/serverless";

export type EffectivePlanTier = "free" | "plus" | "pro" | "lifetime";

export type EffectiveSubscriptionRow = {
  billingPlanTier?: string | null;
  entitlementId?: string | null;
  productId?: string | null;
  store?: string | null;
  environment?: string | null;
  billingStatus?: string | null;
  billingIsActive?: number | null;
  purchasedAt?: string | null;
  expiresAt?: string | null;
  cancelledAt?: string | null;
  billingUpdatedAt?: string | null;
  overridePlanTier?: string | null;
  overrideIsActive?: number | null;
  overrideExpiresAt?: string | null;
  overrideUpdatedAt?: string | null;
};

export type EffectiveSubscription = {
  effectivePlanTier: EffectivePlanTier;
  effectiveIsActive: boolean;
  entitlementId: string;
  productId: string | null;
  store: string | null;
  environment: string;
  status: string;
  purchasedAt: string | null;
  expiresAt: string | null;
  cancelledAt: string | null;
  updatedAt: string;
  source: "revenuecat" | "admin_override" | "free";
  overrideExpiresAt: string | null;
  billingPlanTier: EffectivePlanTier;
  billingIsActive: boolean;
};

export async function effectiveSubscriptionForUser(
  database: Connection,
  userID: string,
  now = new Date(),
): Promise<EffectiveSubscription> {
  const nowISO = now.toISOString();

  // RevenueCat may deliver the expiration webhook after the entitlement has
  // already expired. Normalize the current-state columns on access while
  // preserving plan_tier as historical purchase information.
  await database.run(
    `UPDATE billing_subscriptions
     SET is_active = 0,
         status = 'expired',
         updated_at = ?
     WHERE is_active = 1
       AND expires_at IS NOT NULL
       AND expires_at <= ?
       AND status NOT IN ('expired', 'revoked')`,
    nowISO,
    nowISO,
  );

  const row = (await database.get(
    `WITH ranked_billing AS (
       SELECT b.*,
              ROW_NUMBER() OVER (
                PARTITION BY b.user_id
                ORDER BY
                  CASE
                    WHEN b.is_active = 1
                     AND (b.expires_at IS NULL OR b.expires_at > ?)
                    THEN 0 ELSE 1
                  END,
                  b.updated_at DESC
              ) AS row_number
       FROM billing_subscriptions b
       WHERE b.user_id = ?
     )
     SELECT
       billing.plan_tier AS billingPlanTier,
       billing.entitlement_id AS entitlementId,
       billing.product_id AS productId,
       billing.store,
       billing.environment,
       billing.status AS billingStatus,
       billing.is_active AS billingIsActive,
       billing.purchased_at AS purchasedAt,
       billing.expires_at AS expiresAt,
       billing.cancelled_at AS cancelledAt,
       billing.updated_at AS billingUpdatedAt,
       admin_override.plan_tier AS overridePlanTier,
       admin_override.is_active AS overrideIsActive,
       admin_override.expires_at AS overrideExpiresAt,
       admin_override.updated_at AS overrideUpdatedAt
     FROM users
     LEFT JOIN ranked_billing billing
       ON billing.row_number = 1
     LEFT JOIN admin_plan_overrides admin_override
       ON admin_override.user_id = users.id
      AND (admin_override.expires_at IS NULL OR admin_override.expires_at > ?)
     WHERE users.id = ?
     LIMIT 1`,
    nowISO,
    userID,
    nowISO,
    userID,
  )) as EffectiveSubscriptionRow | null;

  return resolveEffectiveSubscription(row, now);
}

export function resolveEffectiveSubscription(
  row: EffectiveSubscriptionRow | null,
  now = new Date(),
): EffectiveSubscription {
  const nowISO = now.toISOString();
  const billingTier = normalizedTier(row?.billingPlanTier);
  const overrideTier = normalizedTier(row?.overridePlanTier);
  const billingIsActive = row?.billingIsActive === 1
    && (!row.expiresAt || row.expiresAt > nowISO);
  const hasOverride = row?.overridePlanTier != null;
  const overrideIsActive = row?.overrideIsActive === 1 && overrideTier !== "free";

  const effectivePlanTier = hasOverride
    ? (overrideIsActive ? overrideTier : "free")
    : (billingIsActive ? billingTier : "free");
  const source = hasOverride
    ? "admin_override"
    : row?.entitlementId
      ? "revenuecat"
      : "free";

  return {
    effectivePlanTier,
    effectiveIsActive: effectivePlanTier !== "free",
    entitlementId: row?.entitlementId ?? (hasOverride ? "admin_override" : "none"),
    productId: row?.productId ?? null,
    store: row?.store ?? null,
    environment: hasOverride ? "admin" : (row?.environment ?? "none"),
    status: hasOverride
      ? (overrideIsActive ? "active" : "expired")
      : (row?.billingStatus ?? "inactive"),
    purchasedAt: row?.purchasedAt ?? null,
    expiresAt: hasOverride ? (row?.overrideExpiresAt ?? null) : (row?.expiresAt ?? null),
    cancelledAt: row?.cancelledAt ?? null,
    updatedAt: hasOverride
      ? (row?.overrideUpdatedAt ?? nowISO)
      : (row?.billingUpdatedAt ?? nowISO),
    source,
    overrideExpiresAt: row?.overrideExpiresAt ?? null,
    billingPlanTier: billingTier,
    billingIsActive,
  };
}

function normalizedTier(value: string | null | undefined): EffectivePlanTier {
  switch (value?.toLowerCase()) {
  case "plus": return "plus";
  case "pro": return "pro";
  case "lifetime": return "lifetime";
  default: return "free";
  }
}

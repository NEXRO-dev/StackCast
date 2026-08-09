import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type RevenueCatEvent = {
  id?: string;
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  entitlement_id?: string | null;
  entitlement_ids?: string[] | null;
  product_id?: string | null;
  store?: string | null;
  environment?: string | null;
  purchased_at_ms?: number | null;
  expiration_at_ms?: number | null;
  cancelled_at_ms?: number | null;
  original_transaction_id?: string | null;
  transaction_id?: string | null;
  event_timestamp_ms?: number | null;
};

type RevenueCatWebhook = {
  api_version?: string;
  event?: RevenueCatEvent;
};

const activeEventTypes = new Set([
  "INITIAL_PURCHASE",
  "NON_RENEWING_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "PRODUCT_CHANGE",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
  "PURCHASE_REDEEMED",
  "TRANSFER",
]);

const statusByEventType: Record<string, string> = {
  INITIAL_PURCHASE: "active",
  NON_RENEWING_PURCHASE: "active",
  RENEWAL: "active",
  UNCANCELLATION: "active",
  PRODUCT_CHANGE: "active",
  SUBSCRIPTION_EXTENDED: "active",
  TEMPORARY_ENTITLEMENT_GRANT: "active",
  PURCHASE_REDEEMED: "active",
  TRANSFER: "active",
  CANCELLATION: "cancelled",
  BILLING_ISSUE: "billing_issue",
  SUBSCRIPTION_PAUSED: "paused",
  EXPIRATION: "expired",
};

export async function POST(request: Request) {
  const configuredAuthorization = process.env.REVENUECAT_WEBHOOK_AUTHORIZATION?.trim();
  const receivedAuthorization = request.headers.get("authorization")?.trim();

  if (!configuredAuthorization) {
    console.error("RevenueCat webhook authorization is not configured");
    return Response.json({ error: "Webhook is not configured" }, { status: 503 });
  }

  if (!receivedAuthorization || receivedAuthorization !== configuredAuthorization) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  let payload: RevenueCatWebhook;
  try {
    payload = (await request.json()) as RevenueCatWebhook;
  } catch {
    return Response.json({ error: "Invalid JSON" }, { status: 400 });
  }

  const event = payload.event;
  if (!event?.id || !event.app_user_id || !event.type) {
    return Response.json({ error: "Invalid RevenueCat event" }, { status: 400 });
  }

  const entitlementIDs = uniqueStrings([
    ...(event.entitlement_ids ?? []),
    ...(event.entitlement_id ? [event.entitlement_id] : []),
  ]);

  if (entitlementIDs.length === 0) {
    return Response.json({ received: true, processed: 0 });
  }

  const database = getTurso();
  const userID = await findUserID(database, event);

  // Anonymous RevenueCat users and users removed from the app are acknowledged
  // without creating an orphan billing record.
  if (!userID) {
    return Response.json({ received: true, processed: 0 });
  }

  const now = new Date().toISOString();
  const eventTimestamp = event.event_timestamp_ms ?? Date.now();
  const expirationAt = toISOString(event.expiration_at_ms);
  const isActive = resolveActiveState(event.type, event.expiration_at_ms);
  const status = statusByEventType[event.type] ?? "unknown";
  const environment = event.environment === "PRODUCTION" ? "production" : "test";

  for (const entitlementID of entitlementIDs) {
    // The same RevenueCat event may contain multiple entitlements. The suffix
    // keeps the current per-entitlement row key unique.
    const rowEventID = `${event.id}:${entitlementID}`;

    await database.run(
      `INSERT INTO billing_subscriptions (
        id,
        user_id,
        revenuecat_app_user_id,
        entitlement_id,
        product_id,
        plan_tier,
        store,
        environment,
        status,
        is_active,
        purchased_at,
        expires_at,
        cancelled_at,
        original_transaction_id,
        store_transaction_id,
        latest_event_id,
        latest_event_timestamp_ms,
        raw_event_json,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (revenuecat_app_user_id, entitlement_id) DO UPDATE SET
        product_id = COALESCE(excluded.product_id, billing_subscriptions.product_id),
        plan_tier = COALESCE(excluded.plan_tier, billing_subscriptions.plan_tier),
        store = COALESCE(excluded.store, billing_subscriptions.store),
        environment = excluded.environment,
        status = excluded.status,
        is_active = excluded.is_active,
        purchased_at = COALESCE(excluded.purchased_at, billing_subscriptions.purchased_at),
        expires_at = COALESCE(excluded.expires_at, billing_subscriptions.expires_at),
        cancelled_at = COALESCE(excluded.cancelled_at, billing_subscriptions.cancelled_at),
        original_transaction_id = COALESCE(
          excluded.original_transaction_id,
          billing_subscriptions.original_transaction_id
        ),
        store_transaction_id = COALESCE(
          excluded.store_transaction_id,
          billing_subscriptions.store_transaction_id
        ),
        latest_event_id = excluded.latest_event_id,
        latest_event_timestamp_ms = excluded.latest_event_timestamp_ms,
        raw_event_json = excluded.raw_event_json,
        updated_at = excluded.updated_at
      WHERE billing_subscriptions.latest_event_timestamp_ms IS NULL
        OR excluded.latest_event_timestamp_ms >= billing_subscriptions.latest_event_timestamp_ms`,
      rowEventID,
      userID,
      event.app_user_id,
      entitlementID,
      event.product_id ?? null,
      planTierForProduct(event.product_id),
      event.store ?? null,
      environment,
      status,
      isActive ? 1 : 0,
      toISOString(event.purchased_at_ms),
      expirationAt,
      toISOString(event.cancelled_at_ms),
      event.original_transaction_id ?? null,
      event.transaction_id ?? null,
      rowEventID,
      eventTimestamp,
      JSON.stringify(payload),
      now,
      now,
    );
  }

  return Response.json({
    received: true,
    processed: entitlementIDs.length,
  });
}

async function findUserID(
  database: ReturnType<typeof getTurso>,
  event: RevenueCatEvent,
): Promise<string | null> {
  const candidateIDs = uniqueStrings([
    event.app_user_id,
    event.original_app_user_id,
    ...(event.aliases ?? []),
  ]);

  for (const candidateID of candidateIDs) {
    const user = (await database.get(
      "SELECT id FROM users WHERE id = ? LIMIT 1",
      candidateID,
    )) as { id?: string } | undefined;

    if (user?.id) {
      return user.id;
    }
  }

  return null;
}

function uniqueStrings(values: Array<string | null | undefined>): string[] {
  return [...new Set(values.filter((value): value is string => Boolean(value)))];
}

function planTierForProduct(productID: string | null | undefined): string | null {
  const identifier = productID?.toLowerCase() ?? "";

  if (!identifier) return null;
  if (identifier.includes("lifetime") || identifier.includes("one-time") || identifier.includes("onetime")) {
    return "lifetime";
  }
  if (identifier.includes("plus")) return "plus";
  if (identifier.includes("pro")) return "pro";
  return "pro";
}

function toISOString(milliseconds: number | null | undefined): string | null {
  return typeof milliseconds === "number" ? new Date(milliseconds).toISOString() : null;
}

function resolveActiveState(
  eventType: string,
  expirationAtMilliseconds: number | null | undefined,
): boolean {
  if (eventType === "EXPIRATION") {
    return false;
  }

  if (activeEventTypes.has(eventType)) {
    return true;
  }

  // Cancellation, billing issues, and pauses may retain access until the
  // current billing period ends. If RevenueCat supplied an expiration time,
  // use it; otherwise retain access until a later EXPIRATION event arrives.
  if (["CANCELLATION", "BILLING_ISSUE", "SUBSCRIPTION_PAUSED"].includes(eventType)) {
    return expirationAtMilliseconds == null || expirationAtMilliseconds > Date.now();
  }

  return false;
}

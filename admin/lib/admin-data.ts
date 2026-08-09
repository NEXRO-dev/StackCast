import { requireAdminSession } from "@/lib/auth";
import { getDatabase } from "@/lib/db";

const pageSize = 20;

const effectiveBillingCTE = `
  WITH ranked_billing AS (
    SELECT b.*,
           ROW_NUMBER() OVER (
             PARTITION BY b.user_id
             ORDER BY b.is_active DESC, b.updated_at DESC
           ) AS row_number
    FROM billing_subscriptions b
  ),
  valid_overrides AS (
    SELECT *
    FROM admin_plan_overrides
    WHERE expires_at IS NULL OR expires_at > ?
  ),
  effective_users AS (
    SELECT
      u.id,
      u.name,
      u.email,
      u.created_at AS createdAt,
      u.updated_at AS updatedAt,
      p.profile_image_url AS profileImageURL,
      rb.product_id AS productId,
      rb.store,
      rb.environment,
      rb.status AS revenueCatStatus,
      rb.expires_at AS revenueCatExpiresAt,
      rb.updated_at AS billingUpdatedAt,
      vo.plan_tier AS overridePlanTier,
      vo.is_active AS overrideIsActive,
      vo.expires_at AS overrideExpiresAt,
      vo.reason AS overrideReason,
      CASE
        WHEN vo.user_id IS NOT NULL THEN vo.plan_tier
        ELSE COALESCE(rb.plan_tier, 'free')
      END AS planTier,
      CASE
        WHEN vo.user_id IS NOT NULL THEN vo.is_active
        ELSE COALESCE(rb.is_active, 0)
      END AS isActive,
      CASE
        WHEN vo.user_id IS NOT NULL THEN 'admin_override'
        WHEN rb.user_id IS NOT NULL THEN 'revenuecat'
        ELSE 'free'
      END AS planSource
    FROM users u
    LEFT JOIN user_profiles p ON p.user_id = u.id
    LEFT JOIN ranked_billing rb
      ON rb.user_id = u.id AND rb.row_number = 1
    LEFT JOIN valid_overrides vo ON vo.user_id = u.id
  )`;

export type OverviewData = {
  totalUsers: number;
  newUsers7d: number;
  activePaidUsers: number;
  productionPaidUsers: number;
  testPaidUsers: number;
  plusUsers: number;
  proUsers: number;
  activeOverrides: number;
  activeSessions: number;
  onboardingCompleted: number;
  recentUsers: Array<{
    id: string;
    name: string;
    email: string;
    profileImageURL: string | null;
    createdAt: string;
    planTier: string;
    isActive: number;
    planSource: string;
  }>;
  recentBilling: Array<{
    id: string;
    userId: string;
    name: string;
    email: string;
    profileImageURL: string | null;
    productId: string | null;
    planTier: string | null;
    status: string;
    environment: string;
    updatedAt: string;
  }>;
};

export async function getOverviewData(): Promise<OverviewData> {
  await requireAdminSession();
  const database = getDatabase();
  const now = new Date().toISOString();
  const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();

  const [userStats, billingStats, sessionStats, onboardingStats, recentUsers, recentBilling] =
    await Promise.all([
      database.get(
        `SELECT COUNT(*) AS totalUsers,
                SUM(CASE WHEN created_at >= ? THEN 1 ELSE 0 END) AS newUsers7d
         FROM users`,
        sevenDaysAgo,
      ),
      database.get(
        `${effectiveBillingCTE}
         SELECT
           SUM(CASE WHEN isActive = 1 AND planTier != 'free' THEN 1 ELSE 0 END) AS activePaidUsers,
           SUM(CASE WHEN isActive = 1 AND planTier = 'plus' THEN 1 ELSE 0 END) AS plusUsers,
           SUM(CASE WHEN isActive = 1 AND planTier IN ('pro', 'lifetime') THEN 1 ELSE 0 END) AS proUsers,
           SUM(CASE WHEN isActive = 1 AND environment = 'production' THEN 1 ELSE 0 END) AS productionPaidUsers,
           SUM(CASE WHEN isActive = 1 AND environment = 'test' THEN 1 ELSE 0 END) AS testPaidUsers,
           SUM(CASE WHEN planSource = 'admin_override' THEN 1 ELSE 0 END) AS activeOverrides
         FROM effective_users`,
        now,
      ),
      database.get(
        `SELECT COUNT(DISTINCT user_id) AS activeSessions
         FROM auth_sessions
         WHERE expires_at > ?`,
        now,
      ),
      database.get(
        `${effectiveBillingCTE}
         SELECT COUNT(*) AS onboardingCompleted
         FROM effective_users eu
         LEFT JOIN admin_user_metadata aum ON aum.user_id = eu.id
         WHERE COALESCE(
           aum.onboarding_status,
           CASE WHEN eu.isActive = 1 THEN 'completed' ELSE 'not_started' END
         ) = 'completed'`,
        now,
      ),
      database.all(
        `${effectiveBillingCTE}
         SELECT id, name, email, profileImageURL, createdAt, planTier, isActive, planSource
         FROM effective_users
         ORDER BY createdAt DESC
         LIMIT 6`,
        now,
      ),
      database.all(
        `SELECT b.id, b.user_id AS userId, u.name, u.email,
                p.profile_image_url AS profileImageURL,
                b.product_id AS productId, b.plan_tier AS planTier,
                b.status, b.environment, b.updated_at AS updatedAt
         FROM billing_subscriptions b
         JOIN users u ON u.id = b.user_id
         LEFT JOIN user_profiles p ON p.user_id = u.id
         ORDER BY b.updated_at DESC
         LIMIT 6`,
      ),
    ]);

  const users = userStats as Record<string, unknown> | null;
  const billing = billingStats as Record<string, unknown> | null;
  const sessions = sessionStats as Record<string, unknown> | null;
  const onboarding = onboardingStats as Record<string, unknown> | null;

  return {
    totalUsers: numberValue(users?.totalUsers),
    newUsers7d: numberValue(users?.newUsers7d),
    activePaidUsers: numberValue(billing?.activePaidUsers),
    productionPaidUsers: numberValue(billing?.productionPaidUsers),
    testPaidUsers: numberValue(billing?.testPaidUsers),
    plusUsers: numberValue(billing?.plusUsers),
    proUsers: numberValue(billing?.proUsers),
    activeOverrides: numberValue(billing?.activeOverrides),
    activeSessions: numberValue(sessions?.activeSessions),
    onboardingCompleted: numberValue(onboarding?.onboardingCompleted),
    recentUsers: recentUsers as OverviewData["recentUsers"],
    recentBilling: recentBilling as OverviewData["recentBilling"],
  };
}

export type UserGrowthPoint = {
  date: string;
  label: string;
  count: number;
};

export async function getUserGrowthData(): Promise<{
  sevenDays: UserGrowthPoint[];
  thirtyDays: UserGrowthPoint[];
}> {
  await requireAdminSession();
  const database = getDatabase();
  const now = new Date();
  const start = new Date(now);
  start.setHours(0, 0, 0, 0);
  start.setDate(start.getDate() - 29);

  const rows = (await database.all(
    `SELECT date(created_at) AS date, COUNT(*) AS newUsers
     FROM users
     WHERE created_at >= ?
     GROUP BY date(created_at)
     ORDER BY date(created_at) ASC`,
    start.toISOString(),
  )) as Array<{ date: string; newUsers: number | string | bigint }>;

  const dailyCounts = new Map(rows.map((row) => [row.date, numberValue(row.newUsers)]));
  const beforeStart = (await database.get(
    "SELECT COUNT(*) AS count FROM users WHERE created_at < ?",
    start.toISOString(),
  )) as Record<string, unknown> | null;
  const totalUsersBeforeStart = numberValue(beforeStart?.count);
  let runningCount = totalUsersBeforeStart;
  const points: UserGrowthPoint[] = [];

  for (let index = 0; index < 30; index += 1) {
    const date = new Date(start);
    date.setDate(start.getDate() + index);
    const isoDate = date.toISOString().slice(0, 10);
    runningCount += dailyCounts.get(isoDate) ?? 0;
    points.push({
      date: isoDate,
      label: `${date.getMonth() + 1}/${date.getDate()}`,
      count: runningCount,
    });
  }

  return { sevenDays: points.slice(-7), thirtyDays: points };
}

export type UserListItem = {
  id: string;
  name: string;
  email: string;
  profileImageURL: string | null;
  createdAt: string;
  lastSeenAt: string | null;
  planTier: string;
  isActive: number;
  planSource: string;
  revenueCatStatus: string | null;
  overrideExpiresAt: string | null;
};

export async function getUsers(input: {
  query?: string;
  plan?: string;
  page?: number;
}) {
  await requireAdminSession();
  const database = getDatabase();
  const now = new Date().toISOString();
  const query = input.query?.trim().toLowerCase() ?? "";
  const likeQuery = `%${query}%`;
  const plan = ["free", "plus", "pro"].includes(input.plan ?? "")
    ? input.plan!
    : "all";
  const page = Math.max(1, input.page ?? 1);
  const offset = (page - 1) * pageSize;
  const filters = `
    WHERE (? = '' OR lower(eu.name) LIKE ? OR lower(eu.email) LIKE ? OR lower(eu.id) LIKE ?)
      AND (? = 'all' OR eu.planTier = ?)`;

  const [rows, count] = await Promise.all([
    database.all(
      `${effectiveBillingCTE}
       SELECT eu.*,
              (SELECT MAX(last_used_at) FROM auth_sessions s WHERE s.user_id = eu.id) AS lastSeenAt
       FROM effective_users eu
       ${filters}
       ORDER BY eu.createdAt DESC
       LIMIT ? OFFSET ?`,
      now,
      query,
      likeQuery,
      likeQuery,
      likeQuery,
      plan,
      plan,
      pageSize,
      offset,
    ),
    database.get(
      `${effectiveBillingCTE}
       SELECT COUNT(*) AS total
       FROM effective_users eu
       ${filters}`,
      now,
      query,
      likeQuery,
      likeQuery,
      likeQuery,
      plan,
      plan,
    ),
  ]);

  const total = numberValue((count as Record<string, unknown> | null)?.total);
  return {
    users: rows as UserListItem[],
    total,
    page,
    pageSize,
    totalPages: Math.max(1, Math.ceil(total / pageSize)),
    query,
    plan,
  };
}

export type UserDetail = {
  id: string;
  name: string;
  email: string;
  profileImageURL: string | null;
  createdAt: string;
  updatedAt: string;
  lastSeenAt: string | null;
  sessionCount: number;
  planTier: string;
  isActive: number;
  planSource: string;
  overridePlanTier: string | null;
  overrideExpiresAt: string | null;
  overrideReason: string | null;
  productId: string | null;
  store: string | null;
  environment: string | null;
  revenueCatStatus: string | null;
  revenueCatExpiresAt: string | null;
  onboardingStatus: string;
  onboardingNotes: string | null;
  identities: Array<{ provider: string; providerEmail: string | null; createdAt: string }>;
  subscriptions: Array<{
    id: string;
    productId: string | null;
    planTier: string | null;
    status: string;
    isActive: number;
    environment: string;
    purchasedAt: string | null;
    expiresAt: string | null;
    updatedAt: string;
  }>;
  auditLogs: Array<{
    id: string;
    adminEmail: string;
    action: string;
    metadataJSON: string | null;
    createdAt: string;
  }>;
};

export async function getUserDetail(id: string): Promise<UserDetail | null> {
  await requireAdminSession();
  const database = getDatabase();
  const now = new Date().toISOString();

  const [user, identities, subscriptions, auditLogs] = await Promise.all([
    database.get(
      `${effectiveBillingCTE}
       SELECT eu.*,
              (SELECT MAX(last_used_at) FROM auth_sessions s WHERE s.user_id = eu.id) AS lastSeenAt,
              (SELECT COUNT(*) FROM auth_sessions s WHERE s.user_id = eu.id AND s.expires_at > ?) AS sessionCount,
              COALESCE(
                aum.onboarding_status,
                CASE
                  WHEN eu.isActive = 1 THEN 'completed'
                  WHEN EXISTS(SELECT 1 FROM auth_identities ai WHERE ai.user_id = eu.id)
                    OR eu.profileImageURL IS NOT NULL THEN 'in_progress'
                  ELSE 'not_started'
                END
              ) AS onboardingStatus,
              aum.notes AS onboardingNotes
       FROM effective_users eu
       LEFT JOIN admin_user_metadata aum ON aum.user_id = eu.id
       WHERE eu.id = ?
       LIMIT 1`,
      now,
      now,
      id,
    ),
    database.all(
      `SELECT provider, provider_email AS providerEmail, created_at AS createdAt
       FROM auth_identities
       WHERE user_id = ?
       ORDER BY created_at ASC`,
      id,
    ),
    database.all(
      `SELECT id, product_id AS productId, plan_tier AS planTier,
              status, is_active AS isActive, environment,
              purchased_at AS purchasedAt, expires_at AS expiresAt,
              updated_at AS updatedAt
       FROM billing_subscriptions
       WHERE user_id = ?
       ORDER BY updated_at DESC
       LIMIT 20`,
      id,
    ),
    database.all(
      `SELECT id, admin_email AS adminEmail, action,
              metadata_json AS metadataJSON, created_at AS createdAt
       FROM admin_audit_logs
       WHERE target_type = 'user' AND target_id = ?
       ORDER BY created_at DESC
       LIMIT 20`,
      id,
    ),
  ]);

  if (!user) return null;
  const row = user as Omit<UserDetail, "identities" | "subscriptions" | "auditLogs">;
  return {
    ...row,
    sessionCount: numberValue(row.sessionCount),
    identities: identities as UserDetail["identities"],
    subscriptions: subscriptions as UserDetail["subscriptions"],
    auditLogs: auditLogs as UserDetail["auditLogs"],
  };
}

export type BillingListItem = UserListItem & {
  productId: string | null;
  store: string | null;
  environment: string | null;
  revenueCatExpiresAt: string | null;
  billingUpdatedAt: string | null;
};

export async function getBillingData() {
  await requireAdminSession();
  const database = getDatabase();
  const now = new Date().toISOString();
  const [rows, stats] = await Promise.all([
    database.all(
      `${effectiveBillingCTE}
       SELECT eu.*,
              (SELECT MAX(last_used_at) FROM auth_sessions s WHERE s.user_id = eu.id) AS lastSeenAt
       FROM effective_users eu
       WHERE eu.planSource != 'free' OR eu.revenueCatStatus IS NOT NULL
       ORDER BY eu.isActive DESC, COALESCE(eu.billingUpdatedAt, eu.updatedAt) DESC
       LIMIT 200`,
      now,
    ),
    database.get(
      `${effectiveBillingCTE}
       SELECT
         COUNT(*) AS trackedUsers,
         SUM(CASE WHEN isActive = 1 THEN 1 ELSE 0 END) AS activeUsers,
         SUM(CASE WHEN revenueCatStatus = 'billing_issue' THEN 1 ELSE 0 END) AS billingIssues,
         SUM(CASE WHEN revenueCatStatus = 'cancelled' THEN 1 ELSE 0 END) AS cancelledUsers,
         SUM(CASE WHEN planSource = 'admin_override' THEN 1 ELSE 0 END) AS overrides
       FROM effective_users
       WHERE planSource != 'free' OR revenueCatStatus IS NOT NULL`,
      now,
    ),
  ]);
  const value = stats as Record<string, unknown> | null;

  return {
    subscriptions: rows as BillingListItem[],
    trackedUsers: numberValue(value?.trackedUsers),
    activeUsers: numberValue(value?.activeUsers),
    billingIssues: numberValue(value?.billingIssues),
    cancelledUsers: numberValue(value?.cancelledUsers),
    overrides: numberValue(value?.overrides),
  };
}

export type OnboardingUser = {
  id: string;
  name: string;
  email: string;
  profileImageURL: string | null;
  createdAt: string;
  onboardingStatus: string;
  hasGoogle: number;
  hasApple: number;
  hasProfile: number;
  isActive: number;
  planTier: string;
};

export async function getOnboardingData() {
  await requireAdminSession();
  const database = getDatabase();
  const now = new Date().toISOString();
  const rows = (await database.all(
    `${effectiveBillingCTE}
     SELECT eu.id, eu.name, eu.email, eu.profileImageURL, eu.createdAt, eu.isActive, eu.planTier,
            CASE WHEN EXISTS(
              SELECT 1 FROM auth_identities ai
              WHERE ai.user_id = eu.id AND ai.provider = 'google'
            ) THEN 1 ELSE 0 END AS hasGoogle,
            CASE WHEN EXISTS(
              SELECT 1 FROM auth_identities ai
              WHERE ai.user_id = eu.id AND ai.provider = 'apple'
            ) THEN 1 ELSE 0 END AS hasApple,
            CASE WHEN eu.profileImageURL IS NOT NULL THEN 1 ELSE 0 END AS hasProfile,
            COALESCE(
              aum.onboarding_status,
              CASE
                WHEN eu.isActive = 1 THEN 'completed'
                WHEN EXISTS(SELECT 1 FROM auth_identities ai WHERE ai.user_id = eu.id)
                  OR eu.profileImageURL IS NOT NULL THEN 'in_progress'
                ELSE 'not_started'
              END
            ) AS onboardingStatus
     FROM effective_users eu
     LEFT JOIN admin_user_metadata aum ON aum.user_id = eu.id
     ORDER BY eu.createdAt DESC
     LIMIT 200`,
    now,
  )) as OnboardingUser[];

  return {
    users: rows,
    total: rows.length,
    completed: rows.filter((row) => row.onboardingStatus === "completed").length,
    inProgress: rows.filter((row) => row.onboardingStatus === "in_progress").length,
    notStarted: rows.filter((row) => row.onboardingStatus === "not_started").length,
    googleUsers: rows.filter((row) => Boolean(row.hasGoogle)).length,
  };
}

export async function getDatabaseStatus() {
  await requireAdminSession();
  const database = getDatabase();
  const [ping, tables] = await Promise.all([
    database.get("SELECT 1 AS ok"),
    database.get(
      `SELECT COUNT(*) AS count
       FROM sqlite_master
       WHERE type = 'table' AND name NOT LIKE 'sqlite_%'`,
    ),
  ]);

  return {
    connected: numberValue((ping as Record<string, unknown> | null)?.ok) === 1,
    tableCount: numberValue((tables as Record<string, unknown> | null)?.count),
  };
}

function numberValue(value: unknown): number {
  if (typeof value === "bigint") return Number(value);
  if (typeof value === "number") return value;
  if (typeof value === "string") return Number(value) || 0;
  return 0;
}

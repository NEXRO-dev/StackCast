import { auditStatement } from "@/lib/audit";
import { assertSameOrigin, requireAdminApiSession } from "@/lib/auth";
import { getDatabase } from "@/lib/db";

export const runtime = "nodejs";

type PlanInput = {
  planTier?: unknown;
  expiresAt?: unknown;
  reason?: unknown;
};

export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const admin = await requireAdminApiSession();
  if (!admin) return Response.json({ error: "認証が必要です。" }, { status: 401 });
  if (!assertSameOrigin(request)) {
    return Response.json({ error: "不正なリクエストです。" }, { status: 403 });
  }

  const { id } = await context.params;
  const body = (await request.json().catch(() => null)) as PlanInput | null;
  const planTier = typeof body?.planTier === "string" ? body.planTier : "";
  const reason = typeof body?.reason === "string" ? body.reason.trim() : "";

  if (!["revenuecat", "free", "plus", "pro"].includes(planTier)) {
    return Response.json({ error: "プランが正しくありません。" }, { status: 400 });
  }
  if (reason.length < 3 || reason.length > 500) {
    return Response.json({ error: "変更理由を3〜500文字で入力してください。" }, { status: 400 });
  }

  let expiresAt: string | null = null;
  if (typeof body?.expiresAt === "string" && body.expiresAt) {
    const date = new Date(body.expiresAt);
    if (Number.isNaN(date.getTime()) || date.getTime() <= Date.now()) {
      return Response.json({ error: "有効期限は未来の日時を指定してください。" }, { status: 400 });
    }
    expiresAt = date.toISOString();
  }

  const database = getDatabase();
  const user = await database.get("SELECT id FROM users WHERE id = ? LIMIT 1", id);
  if (!user) return Response.json({ error: "ユーザーが見つかりません。" }, { status: 404 });

  const now = new Date().toISOString();
  const audit = auditStatement({
    adminEmail: admin.email,
    action: planTier === "revenuecat" ? "plan_override_cleared" : "plan_override_set",
    targetType: "user",
    targetId: id,
    metadata: { planTier, expiresAt, reason },
  });

  if (planTier === "revenuecat") {
    await database.batch(
      [
        { sql: "DELETE FROM admin_plan_overrides WHERE user_id = ?", args: [id] },
        audit,
      ],
      "immediate",
    );
  } else {
    await database.batch(
      [
        {
          sql: `INSERT INTO admin_plan_overrides
            (user_id, plan_tier, is_active, expires_at, reason, updated_by, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              plan_tier = excluded.plan_tier,
              is_active = excluded.is_active,
              expires_at = excluded.expires_at,
              reason = excluded.reason,
              updated_by = excluded.updated_by,
              updated_at = excluded.updated_at`,
          args: [
            id,
            planTier,
            planTier === "free" ? 0 : 1,
            expiresAt,
            reason,
            admin.email,
            now,
            now,
          ],
        },
        audit,
      ],
      "immediate",
    );
  }

  return Response.json({ updated: true });
}

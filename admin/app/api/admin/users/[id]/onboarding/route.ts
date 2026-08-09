import { auditStatement } from "@/lib/audit";
import { assertSameOrigin, requireAdminApiSession } from "@/lib/auth";
import { getDatabase } from "@/lib/db";

export const runtime = "nodejs";

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
  const body = (await request.json().catch(() => null)) as {
    status?: unknown;
    notes?: unknown;
  } | null;
  const status = typeof body?.status === "string" ? body.status : "";
  const notes = typeof body?.notes === "string" ? body.notes.trim() : "";

  if (!["not_started", "in_progress", "completed"].includes(status)) {
    return Response.json({ error: "ステータスが正しくありません。" }, { status: 400 });
  }
  if (notes.length > 2000) {
    return Response.json({ error: "メモは2000文字以内で入力してください。" }, { status: 400 });
  }

  const database = getDatabase();
  const user = await database.get("SELECT id FROM users WHERE id = ? LIMIT 1", id);
  if (!user) return Response.json({ error: "ユーザーが見つかりません。" }, { status: 404 });

  const now = new Date().toISOString();
  const audit = auditStatement({
    adminEmail: admin.email,
    action: "onboarding_updated",
    targetType: "user",
    targetId: id,
    metadata: { status },
  });

  await database.batch(
    [
      {
        sql: `INSERT INTO admin_user_metadata
          (user_id, onboarding_status, notes, updated_by, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id) DO UPDATE SET
            onboarding_status = excluded.onboarding_status,
            notes = excluded.notes,
            updated_by = excluded.updated_by,
            updated_at = excluded.updated_at`,
        args: [id, status, notes || null, admin.email, now, now],
      },
      audit,
    ],
    "immediate",
  );

  return Response.json({ updated: true });
}

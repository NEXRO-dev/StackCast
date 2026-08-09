import {
  assertSameOrigin,
  createAdminSession,
  getPendingAdmin,
  verifyAdminPassword,
} from "@/lib/auth";
import {
  clearLoginFailures,
  isLoginLocked,
  recordLoginFailure,
} from "@/lib/login-rate-limit";
import { writeAuditLog } from "@/lib/audit";

export const runtime = "nodejs";

export async function POST(request: Request) {
  if (!assertSameOrigin(request)) {
    return Response.json({ error: "不正なリクエストです。" }, { status: 403 });
  }

  const identity = await getPendingAdmin();
  if (!identity) {
    return Response.json(
      { error: "Google認証の有効期限が切れました。もう一度お試しください。" },
      { status: 401 },
    );
  }

  try {
    if (await isLoginLocked(identity.email, request)) {
      return Response.json(
        { error: "試行回数が多すぎます。15分後にもう一度お試しください。" },
        { status: 429 },
      );
    }

    const body = (await request.json().catch(() => null)) as { password?: unknown } | null;
    const password = typeof body?.password === "string" ? body.password : "";

    if (!password || !verifyAdminPassword(password)) {
      await recordLoginFailure(identity.email, request);
      return Response.json({ error: "管理者パスワードが正しくありません。" }, { status: 401 });
    }

    await clearLoginFailures(identity.email, request);
    await createAdminSession(identity);
    await writeAuditLog({
      adminEmail: identity.email,
      action: "admin_login",
      targetType: "admin",
      targetId: identity.email,
    });
    return Response.json({ authenticated: true });
  } catch (error) {
    console.error("Admin password authentication failed", error);
    return Response.json(
      { error: "管理者認証を完了できませんでした。設定を確認してください。" },
      { status: 500 },
    );
  }
}

import { errorResponse } from "@/lib/auth/response";
import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { hashPassword, verifyPassword } from "@/lib/auth/password";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

const passwordPattern = /^(?=.*[A-Za-z])(?=.*\d)(?=.*[^A-Za-z\d]).{8,128}$/;

export async function PATCH(request: Request) {
  const token = bearerToken(request);
  if (!token) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  const body = await request.json().catch(() => null) as {
    currentPassword?: unknown;
    newPassword?: unknown;
  } | null;
  const currentPassword = typeof body?.currentPassword === "string" ? body.currentPassword : "";
  const newPassword = typeof body?.newPassword === "string" ? body.newPassword : "";
  if (!passwordPattern.test(newPassword)) {
    return errorResponse("invalid_input", "Password must be 8–128 characters and include a letter, number, and symbol.", 400);
  }

  try {
    const user = (await getTurso().get(
      `SELECT users.id, users.password_hash AS passwordHash
       FROM auth_sessions JOIN users ON users.id = auth_sessions.user_id
       WHERE auth_sessions.token_hash = ? AND auth_sessions.expires_at > ? LIMIT 1`,
      hashSessionToken(token),
      new Date().toISOString(),
    )) as { id: string; passwordHash: string } | null;
    if (!user) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
    if (user.passwordHash.startsWith("external$")) {
      return errorResponse("password_change_not_allowed", "This account does not use an email password.", 403);
    }
    if (!(await verifyPassword(currentPassword, user.passwordHash))) {
      return errorResponse("invalid_credentials", "The current password is incorrect.", 400);
    }
    await getTurso().run(
      "UPDATE users SET password_hash = ?, updated_at = ? WHERE id = ?",
      await hashPassword(newPassword),
      new Date().toISOString(),
      user.id,
    );
    return Response.json({ updated: true });
  } catch (error) {
    console.error("Password change failed", error);
    return errorResponse("server_error", "Unable to change password.", 500);
  }
}

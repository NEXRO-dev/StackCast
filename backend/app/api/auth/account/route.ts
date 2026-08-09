import { errorResponse } from "@/lib/auth/response";
import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type AccountRow = {
  id: string;
  email: string;
};

export async function DELETE(request: Request) {
  const token = bearerToken(request);

  if (!token) {
    return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  }

  try {
    const now = new Date().toISOString();
    const account = (await getTurso().get(
      `SELECT users.id, users.email
       FROM auth_sessions
       JOIN users ON users.id = auth_sessions.user_id
       WHERE auth_sessions.token_hash = ?
         AND auth_sessions.expires_at > ?
       LIMIT 1`,
      hashSessionToken(token),
      now,
    )) as AccountRow | null;

    if (!account) {
      return errorResponse("unauthorized", "Session is invalid or expired.", 401);
    }

    await getTurso().batch([
      {
        sql: "DELETE FROM auth_email_challenges WHERE email = ?",
        args: [account.email],
      },
      {
        sql: "DELETE FROM auth_enrollment_tokens WHERE email = ?",
        args: [account.email],
      },
      {
        sql: "DELETE FROM auth_sessions WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM auth_identities WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM user_profiles WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM billing_subscriptions WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM users WHERE id = ?",
        args: [account.id],
      },
    ], "immediate");

    return new Response(null, { status: 204 });
  } catch (error) {
    console.error("Account deletion failed", error);
    return errorResponse("server_error", "Unable to delete account.", 500);
  }
}

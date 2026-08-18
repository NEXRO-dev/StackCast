import { errorResponse } from "@/lib/auth/response";
import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { deleteUserAudioObjects } from "@/lib/r2-storage";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type AccountRow = {
  id: string;
  email: string;
};

type AccountUserRow = {
  id: string;
  name: string;
  email: string;
  profileImageURL: string | null;
  preferredLanguage: "japanese" | "english";
};

export async function PATCH(request: Request) {
  const token = bearerToken(request);
  if (!token) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  const body = (await request.json().catch(() => null)) as { preferredLanguage?: unknown } | null;
  const preferredLanguage = body?.preferredLanguage === "english"
    ? "english"
    : body?.preferredLanguage === "japanese"
      ? "japanese"
      : null;
  if (!preferredLanguage) {
    return errorResponse("invalid_input", "Preferred language is invalid.", 400);
  }

  try {
    const database = getTurso();
    const now = new Date().toISOString();
    const user = (await database.get(
      `SELECT users.id, users.name, users.email,
              users.preferred_language AS preferredLanguage,
              user_profiles.profile_image_url AS profileImageURL
       FROM auth_sessions
       JOIN users ON users.id = auth_sessions.user_id
       LEFT JOIN user_profiles ON user_profiles.user_id = users.id
       WHERE auth_sessions.token_hash = ?
         AND auth_sessions.expires_at > ?
       LIMIT 1`,
      hashSessionToken(token),
      now,
    )) as AccountUserRow | null;

    if (!user) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

    await database.run(
      "UPDATE users SET preferred_language = ?, updated_at = ? WHERE id = ?",
      preferredLanguage,
      now,
      user.id,
    );

    return Response.json({ user: { ...user, preferredLanguage } });
  } catch (error) {
    console.error("Preferred language update failed", error);
    return errorResponse("server_error", "Unable to update preferred language.", 500);
  }
}

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

    await deleteUserAudioObjects(account.id);

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

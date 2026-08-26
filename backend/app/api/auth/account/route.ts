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

  const body = (await request.json().catch(() => null)) as { preferredLanguage?: unknown; name?: unknown } | null;
  const preferredLanguage = body?.preferredLanguage === "english"
    ? "english"
    : body?.preferredLanguage === "japanese"
      ? "japanese"
      : null;
  const name = typeof body?.name === "string" ? body.name.trim().slice(0, 100) : null;
  if (!preferredLanguage && !name) {
    return errorResponse("invalid_input", "Profile information is invalid.", 400);
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

    if (preferredLanguage) {
      await database.run(
        "UPDATE users SET preferred_language = ?, updated_at = ? WHERE id = ?",
        preferredLanguage, now, user.id,
      );
    }
    if (name) {
      await database.run(
        "UPDATE users SET name = ?, updated_at = ? WHERE id = ?",
        name, now, user.id,
      );
    }

    return Response.json({ user: { ...user, preferredLanguage: preferredLanguage ?? user.preferredLanguage, name: name ?? user.name } });
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
        sql: "DELETE FROM push_device_tokens WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM saved_articles WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM user_custom_interests WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM user_topic_preferences WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM user_recommendation_profiles WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM recommendation_events WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM user_memory_items WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM daily_cast_jobs WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM daily_news_editions WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM cast_credit_ledger WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM user_credit_periods WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM casts WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM admin_plan_overrides WHERE user_id = ?",
        args: [account.id],
      },
      {
        sql: "DELETE FROM admin_user_metadata WHERE user_id = ?",
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

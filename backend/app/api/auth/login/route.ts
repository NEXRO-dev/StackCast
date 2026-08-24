import { verifyPassword } from "@/lib/auth/password";
import { authResponse, errorResponse } from "@/lib/auth/response";
import { createSession } from "@/lib/auth/session";
import { validateLoginInput } from "@/lib/auth/validation";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type UserRow = {
  id: string;
  name: string;
  email: string;
  password_hash: string;
  profileImageURL: string | null;
  preferredLanguage: "japanese" | "english";
  onboardingCompletedAt: string | null;
};

export async function POST(request: Request) {
  const input = validateLoginInput(await request.json().catch(() => null));

  if (!input) {
    return invalidCredentialsResponse();
  }

  try {
    const user = (await getTurso().get(
      `SELECT users.id, users.name, users.email, users.password_hash,
              users.preferred_language AS preferredLanguage,
              user_profiles.profile_image_url AS profileImageURL,
              user_recommendation_profiles.onboarding_completed_at AS onboardingCompletedAt
       FROM users
       LEFT JOIN user_profiles ON user_profiles.user_id = users.id
       LEFT JOIN user_recommendation_profiles ON user_recommendation_profiles.user_id = users.id
       WHERE users.email = ?
       LIMIT 1`,
      input.email,
    )) as UserRow | null;

    if (!user) {
      return errorResponse(
        "account_not_found",
        "No account exists for this email address. Please sign up first.",
        401,
      );
    }

    if (!(await verifyPassword(input.password, user.password_hash))) {
      return invalidCredentialsResponse();
    }

    const session = createSession();
    await getTurso().run(
      `INSERT INTO auth_sessions
        (id, user_id, token_hash, expires_at, created_at, last_used_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
      session.id,
      user.id,
      session.tokenHash,
      session.expiresAt,
      session.createdAt,
      session.createdAt,
    );

    return authResponse(
      {
        id: user.id,
        name: user.name,
        email: user.email,
        profileImageURL: user.profileImageURL,
        preferredLanguage: user.preferredLanguage,
      },
      session.token,
      session.expiresAt,
      !user.onboardingCompletedAt,
    );
  } catch (error) {
    console.error("Login failed", error);
    return errorResponse("server_error", "Unable to log in.", 500);
  }
}

function invalidCredentialsResponse(): Response {
  return errorResponse(
    "invalid_credentials",
    "Email or password is incorrect.",
    401,
  );
}

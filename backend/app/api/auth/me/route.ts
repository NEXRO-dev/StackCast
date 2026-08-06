import { errorResponse } from "@/lib/auth/response";
import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type SessionUserRow = {
  id: string;
  name: string;
  email: string;
  profileImageURL: string | null;
};

export async function GET(request: Request) {
  const token = bearerToken(request);

  if (!token) {
    return unauthorizedResponse();
  }

  try {
    const now = new Date().toISOString();
    const tokenHash = hashSessionToken(token);
    const user = (await getTurso().get(
      `SELECT users.id, users.name, users.email,
              user_profiles.profile_image_url AS profileImageURL
       FROM auth_sessions
       JOIN users ON users.id = auth_sessions.user_id
       LEFT JOIN user_profiles ON user_profiles.user_id = users.id
       WHERE auth_sessions.token_hash = ?
         AND auth_sessions.expires_at > ?
       LIMIT 1`,
      tokenHash,
      now,
    )) as SessionUserRow | null;

    if (!user) {
      return unauthorizedResponse();
    }

    await getTurso().run(
      "UPDATE auth_sessions SET last_used_at = ? WHERE token_hash = ?",
      now,
      tokenHash,
    );

    return Response.json({ user });
  } catch (error) {
    console.error("Session validation failed", error);
    return errorResponse("server_error", "Unable to validate session.", 500);
  }
}

function unauthorizedResponse(): Response {
  return errorResponse("unauthorized", "Session is invalid or expired.", 401);
}

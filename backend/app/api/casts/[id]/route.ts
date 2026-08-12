import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { errorResponse } from "@/lib/auth/response";
import { getCast } from "@/lib/cast/pipeline";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function GET(
  request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  const { id } = await context.params;
  try {
    return Response.json({ cast: await getCast(userID, id) });
  } catch (error) {
    if (error instanceof Error && error.message === "CAST_NOT_FOUND") {
      return errorResponse("not_found", "Cast was not found.", 404);
    }
    console.error("Cast lookup failed", error);
    return errorResponse("server_error", "Unable to load the cast.", 500);
  }
}

async function authenticatedUserID(request: Request): Promise<string | null> {
  const token = bearerToken(request);
  if (!token) return null;

  const session = (await getTurso().get(
    `SELECT user_id AS userID
     FROM auth_sessions
     WHERE token_hash = ? AND expires_at > ?
     LIMIT 1`,
    hashSessionToken(token),
    new Date().toISOString(),
  )) as { userID?: string } | null;

  return session?.userID ?? null;
}

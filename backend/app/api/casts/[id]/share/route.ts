import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { errorResponse } from "@/lib/auth/response";
import { createOrGetCastShare, revokeCastShare } from "@/lib/cast/sharing";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  const { id } = await context.params;
  try {
    const { token } = await createOrGetCastShare(userID, id);
    const origin = process.env.PUBLIC_APP_URL?.trim() || new URL(request.url).origin;
    return Response.json({ shareURL: new URL(`/c/${token}`, origin).toString() });
  } catch (error) {
    if (error instanceof Error && error.message === "CAST_NOT_SHAREABLE") {
      return errorResponse("not_shareable", "This Cast cannot be shared.", 404);
    }
    console.error("Cast share creation failed", { castID: id, userID, error });
    return errorResponse("server_error", "Unable to create a share link.", 500);
  }
}

export async function DELETE(
  request: Request,
  context: { params: Promise<{ id: string }> },
) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  const { id } = await context.params;
  try {
    await revokeCastShare(userID, id);
    return new Response(null, { status: 204 });
  } catch (error) {
    if (error instanceof Error && error.message === "CAST_SHARE_NOT_FOUND") {
      return errorResponse("not_found", "Share link was not found.", 404);
    }
    console.error("Cast share revocation failed", { castID: id, userID, error });
    return errorResponse("server_error", "Unable to revoke the share link.", 500);
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

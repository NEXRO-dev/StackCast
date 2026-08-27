import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { errorResponse } from "@/lib/auth/response";
import { enqueueCast, listCasts, type CreateCastInput } from "@/lib/cast/pipeline";
import { getTurso } from "@/lib/turso";
import { randomUUID } from "node:crypto";

export const runtime = "nodejs";
export const maxDuration = 300;

export async function GET(request: Request) {
  let userID: string | null;
  try {
    userID = await authenticatedUserID(request);
  } catch (error) {
    console.error("Cast authentication database lookup failed", error);
    return errorResponse("database_unavailable", "Database is temporarily unavailable. Please try again.", 503);
  }
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  try {
    return Response.json({ casts: await listCasts(userID) });
  } catch (error) {
    console.error("Cast list failed", error);
    return errorResponse("server_error", "Unable to load casts.", 500);
  }
}

export async function POST(request: Request) {
  const requestID = randomUUID();
  let userID: string | null;
  try {
    userID = await authenticatedUserID(request);
  } catch (error) {
    console.error("Cast authentication database lookup failed", { requestID, error });
    return errorResponse("database_unavailable", "Database is temporarily unavailable. Please try again.", 503);
  }
  if (!userID) {
    console.warn("[cast] request rejected", { requestID, reason: "unauthorized" });
    return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  }

  let input: CreateCastInput;
  try {
    input = (await request.json()) as CreateCastInput;
  } catch {
    console.warn("[cast] request rejected", { requestID, userID, reason: "invalid_json" });
    return errorResponse("invalid_request", "Request body must be valid JSON.", 400);
  }

  console.info("[cast] request received", {
    requestID,
    userID,
    sourceCount: Array.isArray(input.sources) ? input.sources.length : null,
    durationMinutes: input.durationMinutes ?? 10,
  });

  try {
    // Manual Cast generation is queued so Pro users can receive priority
    // processing while keeping the same backend worker for every plan.
    const cast = await enqueueCast(userID, { ...input, internalKind: undefined });
    console.info("[cast] request completed", { requestID, userID, castID: cast.id, status: cast.status });
    return Response.json({ cast }, { status: 200 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "CAST_GENERATION_FAILED";
    console.error("[cast] request failed", {
      requestID,
      userID,
      code: message,
      stack: error instanceof Error ? error.stack : undefined,
    });
    if (message === "CAST_REQUIRES_THREE_TO_FOUR_SOURCES") {
      return errorResponse("invalid_sources", "Select one to four articles in development, or three to four articles in production.", 400);
    }
    if (message === "CAST_INSUFFICIENT_CREDITS") {
      return errorResponse("insufficient_credits", "You do not have enough Cast credits.", 402);
    }
    if (message.startsWith("CAST_CONTENT_NOT_ALLOWED")) {
      return errorResponse("content_not_allowed", "This article content cannot be processed into a Cast.", 422);
    }
    if (message.startsWith("CONTENT_MODERATION_FAILED_")) {
      return errorResponse("moderation_unavailable", "Content safety screening is temporarily unavailable. Please try again later.", 503);
    }
    if (message.startsWith("OPENAI_")) {
      return errorResponse("ai_generation_failed", "The AI summary could not be generated. Please try again later.", 502);
    }
    if (message.startsWith("FISH_AUDIO_")) {
      return errorResponse("audio_generation_failed", "The audio could not be generated. Please try again later.", 502);
    }
    if (message.startsWith("SOURCE_")) {
      return errorResponse("source_fetch_failed", "One of the selected articles could not be read. Please try different articles.", 422);
    }
    if (message === "CAST_NOT_FOUND") {
      return errorResponse("not_found", "Cast was not found.", 404);
    }
    console.error("Cast generation failed", error);
    return errorResponse("cast_generation_failed", "Unable to generate the cast.", 502);
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

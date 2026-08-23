import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  const body = (await request.json().catch(() => null)) as { token?: unknown; environment?: unknown } | null;
  const token = typeof body?.token === "string" ? body.token.trim() : "";
  const environment = body?.environment === "production" ? "production" : "sandbox";
  if (!token || token.length > 512) return errorResponse("invalid_request", "A valid device token is required.", 400);
  const now = new Date().toISOString();
  await getTurso().run(
    `INSERT INTO push_device_tokens (token, user_id, environment, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(token) DO UPDATE SET user_id = excluded.user_id, environment = excluded.environment, updated_at = excluded.updated_at`,
    token, userID, environment, now, now,
  );
  return Response.json({ registered: true });
}

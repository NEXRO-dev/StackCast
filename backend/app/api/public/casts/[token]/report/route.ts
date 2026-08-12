import { createHash, randomUUID } from "node:crypto";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

const allowedReasons = new Set(["inappropriate", "copyright", "privacy", "other"]);

export async function POST(
  request: Request,
  context: { params: Promise<{ token: string }> },
) {
  const { token } = await context.params;
  const cast = (await getTurso().get(
    `SELECT casts.id AS castID
     FROM cast_shares
     INNER JOIN casts ON casts.id = cast_shares.cast_id
     WHERE cast_shares.token = ? AND casts.status = 'completed'
     LIMIT 1`,
    token,
  )) as { castID?: string } | null;

  if (!cast?.castID) {
    return Response.json({ error: { code: "not_found", message: "Cast was not found." } }, { status: 404 });
  }

  let body: { reason?: string; details?: string } = {};
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return Response.json({ error: { code: "invalid_request", message: "Request body must be valid JSON." } }, { status: 400 });
  }

  const reason = body.reason?.trim() ?? "";
  if (!allowedReasons.has(reason)) {
    return Response.json({ error: { code: "invalid_reason", message: "Select a valid report reason." } }, { status: 400 });
  }

  const details = body.details?.trim().slice(0, 2_000) || null;
  const forwardedFor = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const reporterKey = createHash("sha256").update(forwardedFor).digest("hex");
  const recent = (await getTurso().get(
    `SELECT id FROM cast_reports
     WHERE cast_id = ? AND reporter_key = ? AND created_at > ?
     LIMIT 1`,
    cast.castID,
    reporterKey,
    new Date(Date.now() - 24 * 60 * 60 * 1_000).toISOString(),
  )) as { id?: string } | null;

  if (!recent?.id) {
    await getTurso().run(
      `INSERT INTO cast_reports
       (id, cast_id, share_token, reason, details, reporter_key, status, created_at)
       VALUES (?, ?, ?, ?, ?, ?, 'open', ?)`,
      randomUUID(),
      cast.castID,
      token,
      reason,
      details,
      reporterKey,
      new Date().toISOString(),
    );
  }

  return Response.json({ reported: true });
}


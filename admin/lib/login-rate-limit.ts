import { createHash } from "node:crypto";
import { getDatabase } from "@/lib/db";

const maximumAttempts = 5;
const windowMilliseconds = 15 * 60 * 1000;
const lockMilliseconds = 15 * 60 * 1000;

type AttemptRow = {
  attemptCount: number;
  windowStartedAt: string;
  lockedUntil: string | null;
};

export async function isLoginLocked(email: string, request: Request) {
  const key = attemptKey(email, request);
  const row = (await getDatabase().get(
    `SELECT attempt_count AS attemptCount,
            window_started_at AS windowStartedAt,
            locked_until AS lockedUntil
     FROM admin_login_attempts
     WHERE attempt_key = ?
     LIMIT 1`,
    key,
  )) as AttemptRow | null;

  return Boolean(row?.lockedUntil && new Date(row.lockedUntil).getTime() > Date.now());
}

export async function recordLoginFailure(email: string, request: Request) {
  const key = attemptKey(email, request);
  const now = new Date();
  const current = (await getDatabase().get(
    `SELECT attempt_count AS attemptCount,
            window_started_at AS windowStartedAt,
            locked_until AS lockedUntil
     FROM admin_login_attempts
     WHERE attempt_key = ?
     LIMIT 1`,
    key,
  )) as AttemptRow | null;

  const windowExpired =
    !current ||
    now.getTime() - new Date(current.windowStartedAt).getTime() > windowMilliseconds;
  const attemptCount = windowExpired ? 1 : current.attemptCount + 1;
  const lockedUntil =
    attemptCount >= maximumAttempts
      ? new Date(now.getTime() + lockMilliseconds).toISOString()
      : null;

  await getDatabase().run(
    `INSERT INTO admin_login_attempts
       (attempt_key, attempt_count, window_started_at, locked_until, updated_at)
     VALUES (?, ?, ?, ?, ?)
     ON CONFLICT(attempt_key) DO UPDATE SET
       attempt_count = excluded.attempt_count,
       window_started_at = excluded.window_started_at,
       locked_until = excluded.locked_until,
       updated_at = excluded.updated_at`,
    key,
    attemptCount,
    windowExpired ? now.toISOString() : current.windowStartedAt,
    lockedUntil,
    now.toISOString(),
  );
}

export async function clearLoginFailures(email: string, request: Request) {
  await getDatabase().run(
    "DELETE FROM admin_login_attempts WHERE attempt_key = ?",
    attemptKey(email, request),
  );
}

function attemptKey(email: string, request: Request) {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const address = forwarded || request.headers.get("x-real-ip") || "unknown";
  return createHash("sha256")
    .update(`${email.toLowerCase()}|${address}`)
    .digest("hex");
}

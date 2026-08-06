import { sendVerificationEmail } from "@/lib/auth/email";
import {
  createEmailChallenge,
  requesterHash,
  requesterIdentifier,
} from "@/lib/auth/otp";
import { errorResponse } from "@/lib/auth/response";
import { validateEmailRequestInput } from "@/lib/auth/validation";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type CountRow = { count: number | string };
type LatestRow = { created_at: string };

const resendCooldownMilliseconds = 60 * 1000;
const hourlyEmailLimit = 5;
const hourlyRequesterLimit = 20;

export async function POST(request: Request) {
  const input = validateEmailRequestInput(
    await request.json().catch(() => null),
  );

  if (!input) {
    return errorResponse("invalid_input", "Email address is invalid.", 400);
  }

  try {
    const now = Date.now();
    const hourAgo = new Date(now - 60 * 60 * 1000).toISOString();
    const requestHash = requesterHash(request);
    const [latest, emailCount, requesterCount] = await Promise.all([
      getTurso().get(
        `SELECT created_at FROM auth_email_challenges
         WHERE email = ? ORDER BY created_at DESC LIMIT 1`,
        input.email,
      ) as Promise<LatestRow | null>,
      getTurso().get(
        `SELECT COUNT(*) AS count FROM auth_email_challenges
         WHERE email = ? AND created_at >= ?`,
        input.email,
        hourAgo,
      ) as Promise<CountRow | null>,
      getTurso().get(
        `SELECT COUNT(*) AS count FROM auth_email_challenges
         WHERE requester_hash = ? AND created_at >= ?`,
        requestHash,
        hourAgo,
      ) as Promise<CountRow | null>,
    ]);

    const tooSoon =
      latest && now - new Date(latest.created_at).getTime() < resendCooldownMilliseconds;
    const rateLimited =
      Number(emailCount?.count ?? 0) >= hourlyEmailLimit ||
      Number(requesterCount?.count ?? 0) >= hourlyRequesterLimit;

    if (tooSoon || rateLimited) {
      return acceptedResponse();
    }

    const challenge = createEmailChallenge(
      input.email,
      requesterIdentifier(request),
    );
    await getTurso().run(
      `INSERT INTO auth_email_challenges
        (id, email, code_hash, requester_hash, attempts, max_attempts,
         expires_at, consumed_at, created_at)
       VALUES (?, ?, ?, ?, 0, 5, ?, NULL, ?)`,
      challenge.id,
      input.email,
      challenge.codeHash,
      challenge.requesterHash,
      challenge.expiresAt,
      challenge.createdAt,
    );

    try {
      await sendVerificationEmail({
        to: input.email,
        code: challenge.code,
        idempotencyKey: `email-verification/${challenge.id}`,
      });
    } catch (error) {
      await getTurso().run(
        "DELETE FROM auth_email_challenges WHERE id = ?",
        challenge.id,
      );
      throw error;
    }

    return acceptedResponse();
  } catch (error) {
    console.error("Verification email request failed", error);
    return errorResponse(
      "email_delivery_failed",
      "Unable to send a verification email.",
      503,
    );
  }
}

function acceptedResponse(): Response {
  return Response.json(
    { accepted: true, expiresInSeconds: 600, resendAfterSeconds: 60 },
    { status: 202 },
  );
}

import {
  createEnrollmentToken,
  verifyChallengeCode,
} from "@/lib/auth/otp";
import { createAuthenticatedResponse } from "@/lib/auth/account";
import { errorResponse } from "@/lib/auth/response";
import { validateEmailCodeInput } from "@/lib/auth/validation";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type ChallengeRow = {
  id: string;
  code_hash: string;
  attempts: number;
  max_attempts: number;
  expires_at: string;
};

type UserRow = {
  id: string;
  name: string;
  email: string;
  profileImageURL: string | null;
};

export async function POST(request: Request) {
  const input = validateEmailCodeInput(
    await request.json().catch(() => null),
  );

  if (!input) {
    return invalidCodeResponse();
  }

  try {
    const challenge = (await getTurso().get(
      `SELECT id, code_hash, attempts, max_attempts, expires_at
       FROM auth_email_challenges
       WHERE email = ? AND consumed_at IS NULL
       ORDER BY created_at DESC LIMIT 1`,
      input.email,
    )) as ChallengeRow | null;
    const now = new Date();

    if (
      !challenge ||
      challenge.attempts >= challenge.max_attempts ||
      new Date(challenge.expires_at) <= now
    ) {
      return invalidCodeResponse();
    }

    await getTurso().run(
      "UPDATE auth_email_challenges SET attempts = attempts + 1 WHERE id = ?",
      challenge.id,
    );

    if (
      !verifyChallengeCode(
        challenge.id,
        input.email,
        input.code,
        challenge.code_hash,
      )
    ) {
      return invalidCodeResponse();
    }

    const existingUser = (await getTurso().get(
      `SELECT users.id, users.name, users.email,
              user_profiles.profile_image_url AS profileImageURL
       FROM users
       LEFT JOIN user_profiles ON user_profiles.user_id = users.id
       WHERE users.email = ? LIMIT 1`,
      input.email,
    )) as UserRow | null;

    if (existingUser) {
      await getTurso().run(
        `UPDATE auth_email_challenges SET consumed_at = ?
         WHERE id = ? AND consumed_at IS NULL`,
        now.toISOString(),
        challenge.id,
      );
      return createAuthenticatedResponse(existingUser);
    }

    const enrollment = createEnrollmentToken(input.email);
    const consumedAt = now.toISOString();
    await getTurso().batch(
      [
        {
          sql: `UPDATE auth_email_challenges SET consumed_at = ?
                WHERE id = ? AND consumed_at IS NULL`,
          args: [consumedAt, challenge.id],
        },
        {
          sql: `INSERT INTO auth_enrollment_tokens
            (id, email, token_hash, expires_at, consumed_at, created_at)
            VALUES (?, ?, ?, ?, NULL, ?)`,
          args: [
            enrollment.id,
            enrollment.email,
            enrollment.tokenHash,
            enrollment.expiresAt,
            enrollment.createdAt,
          ],
        },
      ],
      "immediate",
    );

    return Response.json({
      mode: "enrollment",
      enrollmentToken: enrollment.token,
      expiresAt: enrollment.expiresAt,
    });
  } catch (error) {
    console.error("Verification code check failed", error);
    return errorResponse("server_error", "Unable to verify code.", 500);
  }
}

function invalidCodeResponse(): Response {
  return errorResponse(
    "invalid_verification_code",
    "The verification code is invalid or expired.",
    400,
  );
}

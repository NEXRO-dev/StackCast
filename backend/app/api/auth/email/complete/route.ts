import { randomUUID } from "node:crypto";
import { hashEnrollmentToken } from "@/lib/auth/otp";
import { hashPassword } from "@/lib/auth/password";
import { authResponse, errorResponse } from "@/lib/auth/response";
import { createSession } from "@/lib/auth/session";
import { validateCompleteEnrollmentInput } from "@/lib/auth/validation";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type EnrollmentRow = {
  id: string;
  email: string;
  expires_at: string;
};

export async function POST(request: Request) {
  const input = validateCompleteEnrollmentInput(
    await request.json().catch(() => null),
  );

  if (!input) {
    return errorResponse("invalid_input", "Account details are invalid.", 400);
  }

  try {
    const enrollment = (await getTurso().get(
      `SELECT id, email, expires_at FROM auth_enrollment_tokens
       WHERE token_hash = ? AND consumed_at IS NULL LIMIT 1`,
      hashEnrollmentToken(input.enrollmentToken),
    )) as EnrollmentRow | null;
    const now = new Date().toISOString();

    if (!enrollment || enrollment.expires_at <= now) {
      return errorResponse(
        "invalid_enrollment_token",
        "Email verification has expired. Request a new code.",
        401,
      );
    }

    const existingUser = await getTurso().get(
      "SELECT id FROM users WHERE email = ? LIMIT 1",
      enrollment.email,
    );
    if (existingUser) {
      return errorResponse(
        "email_already_exists",
        "An account with this email already exists.",
        409,
      );
    }

    const user = {
      id: randomUUID(),
      name: input.name,
      email: enrollment.email,
      profileImageURL: null,
    };
    const passwordHash = await hashPassword(input.password);
    const session = createSession();

    await getTurso().batch(
      [
        {
          sql: `UPDATE auth_enrollment_tokens SET consumed_at = ?
                WHERE id = ? AND consumed_at IS NULL`,
          args: [now, enrollment.id],
        },
        {
          sql: `INSERT INTO users
            (id, name, email, password_hash, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)`,
          args: [user.id, user.name, user.email, passwordHash, now, now],
        },
        {
          sql: `INSERT INTO auth_sessions
            (id, user_id, token_hash, expires_at, created_at, last_used_at)
            VALUES (?, ?, ?, ?, ?, ?)`,
          args: [
            session.id,
            user.id,
            session.tokenHash,
            session.expiresAt,
            session.createdAt,
            session.createdAt,
          ],
        },
      ],
      "immediate",
    );

    return authResponse(user, session.token, session.expiresAt, 201);
  } catch (error) {
    if (error instanceof Error && /unique constraint/i.test(error.message)) {
      return errorResponse(
        "email_already_exists",
        "An account with this email already exists.",
        409,
      );
    }
    console.error("Verified account creation failed", error);
    return errorResponse("server_error", "Unable to create account.", 500);
  }
}

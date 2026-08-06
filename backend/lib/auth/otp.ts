import {
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  randomUUID,
  timingSafeEqual,
} from "node:crypto";

const otpLifetimeMilliseconds = 10 * 60 * 1000;
const enrollmentLifetimeMilliseconds = 10 * 60 * 1000;

export function createEmailChallenge(email: string, requester: string) {
  const code = randomInt(0, 1_000_000).toString().padStart(6, "0");
  const createdAt = new Date();
  const id = randomUUID();

  return {
    id,
    code,
    codeHash: hmac(`${id}:${email}:${code}`),
    requesterHash: hmac(`requester:${requester}`),
    createdAt: createdAt.toISOString(),
    expiresAt: new Date(
      createdAt.getTime() + otpLifetimeMilliseconds,
    ).toISOString(),
  };
}

export function verifyChallengeCode(
  challengeId: string,
  email: string,
  code: string,
  expectedHash: string,
): boolean {
  return safeEqual(hmac(`${challengeId}:${email}:${code}`), expectedHash);
}

export function createEnrollmentToken(email: string) {
  const token = randomBytes(32).toString("base64url");
  const createdAt = new Date();

  return {
    id: randomUUID(),
    email,
    token,
    tokenHash: hashEnrollmentToken(token),
    createdAt: createdAt.toISOString(),
    expiresAt: new Date(
      createdAt.getTime() + enrollmentLifetimeMilliseconds,
    ).toISOString(),
  };
}

export function hashEnrollmentToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function requesterIdentifier(request: Request): string {
  const forwardedFor = request.headers.get("x-forwarded-for")?.split(",")[0];
  return forwardedFor?.trim() || "unknown";
}

export function requesterHash(request: Request): string {
  return hmac(`requester:${requesterIdentifier(request)}`);
}

function hmac(value: string): string {
  return createHmac("sha256", otpSecret()).update(value).digest("hex");
}

function otpSecret(): string {
  const configured = process.env.AUTH_OTP_SECRET?.trim();

  if (configured) {
    return configured;
  }

  if (process.env.NODE_ENV !== "production") {
    return "tsundoku-development-only-otp-secret-change-me";
  }

  throw new Error("Missing required environment variable: AUTH_OTP_SECRET");
}

function safeEqual(actual: string, expected: string): boolean {
  const actualBuffer = Buffer.from(actual);
  const expectedBuffer = Buffer.from(expected);
  return (
    actualBuffer.length === expectedBuffer.length &&
    timingSafeEqual(actualBuffer, expectedBuffer)
  );
}

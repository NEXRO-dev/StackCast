import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import { cache } from "react";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import {
  createRemoteJWKSet,
  jwtVerify,
  SignJWT,
  type JWTPayload,
} from "jose";
import { getDatabase, requiredEnvironmentVariable } from "@/lib/db";

const sessionCookieName = "stashcast_admin_session";
const pendingCookieName = "stashcast_admin_pending";
const oauthCookieName = "stashcast_admin_oauth";
const sessionLifetimeSeconds = 12 * 60 * 60;
const pendingLifetimeSeconds = 10 * 60;
const googleKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
);

export type AdminIdentity = {
  email: string;
  name: string;
  picture: string | null;
};

type AdminTokenPayload = JWTPayload &
  AdminIdentity & {
    purpose: "pending" | "session";
    role: "admin";
  };

export async function verifyGoogleCredential(
  credential: string,
): Promise<AdminIdentity> {
  const clientId = googleClientId();
  const { payload } = await jwtVerify(credential, googleKeys, {
    audience: clientId,
    issuer: ["https://accounts.google.com", "accounts.google.com"],
  });

  const email = stringClaim(payload, "email")?.toLowerCase();
  if (!payload.sub || !email || payload.email_verified !== true) {
    throw new Error("Googleアカウントのメールアドレスを確認できませんでした。");
  }

  if (!allowedAdminEmails().has(email)) {
    throw new Error("このGoogleアカウントには管理画面へのアクセス権がありません。");
  }

  return {
    email,
    name: stringClaim(payload, "name") ?? email.split("@")[0] ?? "Admin",
    picture: httpsURLClaim(payload, "picture"),
  };
}

export async function beginGoogleOAuth(request: Request): Promise<URL> {
  const state = randomBytes(24).toString("base64url");
  const verifier = randomBytes(48).toString("base64url");
  const challenge = createHash("sha256").update(verifier).digest("base64url");
  const oauthToken = await new SignJWT({ purpose: "oauth", state, verifier })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime(`${pendingLifetimeSeconds}s`)
    .sign(sessionSecret());

  (await cookies()).set(
    oauthCookieName,
    oauthToken,
    cookieOptions(pendingLifetimeSeconds),
  );

  const authorizationURL = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authorizationURL.search = new URLSearchParams({
    client_id: googleClientIdOrThrow(),
    redirect_uri: googleRedirectURI(request),
    response_type: "code",
    scope: "openid email profile",
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
    prompt: "select_account",
  }).toString();
  return authorizationURL;
}

export async function completeGoogleOAuth(
  request: Request,
  code: string,
  returnedState: string,
): Promise<AdminIdentity> {
  const oauthToken = (await cookies()).get(oauthCookieName)?.value;
  if (!oauthToken) throw new Error("Google認証の有効期限が切れました。");

  const { payload } = await jwtVerify(oauthToken, sessionSecret(), {
    algorithms: ["HS256"],
  });
  const expectedState = typeof payload.state === "string" ? payload.state : "";
  const verifier = typeof payload.verifier === "string" ? payload.verifier : "";
  if (payload.purpose !== "oauth" || !safeEqual(returnedState, expectedState) || !verifier) {
    throw new Error("Google認証の状態を確認できませんでした。");
  }

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: googleClientIdOrThrow(),
      client_secret: requiredEnvironmentVariable("GOOGLE_CLIENT_SECRET"),
      redirect_uri: googleRedirectURI(request),
      grant_type: "authorization_code",
      code_verifier: verifier,
    }),
    cache: "no-store",
  });
  const tokenBody = (await tokenResponse.json().catch(() => null)) as {
    id_token?: unknown;
    error_description?: unknown;
  } | null;
  if (!tokenResponse.ok || typeof tokenBody?.id_token !== "string") {
    throw new Error(
      typeof tokenBody?.error_description === "string"
        ? tokenBody.error_description
        : "Google認証コードを確認できませんでした。",
    );
  }

  return verifyGoogleCredential(tokenBody.id_token);
}

export async function clearGoogleOAuth() {
  (await cookies()).delete(oauthCookieName);
}

export async function createPendingAdmin(identity: AdminIdentity) {
  const token = await signAdminToken(identity, "pending", pendingLifetimeSeconds);
  const cookieStore = await cookies();
  cookieStore.set(pendingCookieName, token, cookieOptions(pendingLifetimeSeconds));
}

export async function createAdminSession(identity: AdminIdentity) {
  const token = await signAdminToken(identity, "session", sessionLifetimeSeconds);
  const cookieStore = await cookies();
  cookieStore.set(sessionCookieName, token, cookieOptions(sessionLifetimeSeconds));
  cookieStore.delete(pendingCookieName);
}

export async function clearAdminAuthentication() {
  const cookieStore = await cookies();
  cookieStore.delete(sessionCookieName);
  cookieStore.delete(pendingCookieName);
  cookieStore.delete(oauthCookieName);
}

export async function clearPendingAdmin() {
  (await cookies()).delete(pendingCookieName);
}

export const getAdminSession = cache(async (): Promise<AdminIdentity | null> => {
  const token = (await cookies()).get(sessionCookieName)?.value;
  const payload = await verifyAdminToken(token, "session");

  if (!payload || !allowedAdminEmails().has(payload.email.toLowerCase())) {
    return null;
  }

  const identity = identityFromPayload(payload);

  // Prefer the image persisted in the service DB, while keeping the Google
  // image as a safe fallback when this admin is not an app user.
  try {
    const row = (await getDatabase().get(
      `SELECT user_profiles.profile_image_url AS profileImageURL
       FROM users
       LEFT JOIN user_profiles ON user_profiles.user_id = users.id
       WHERE lower(users.email) = lower(?)
       LIMIT 1`,
      identity.email,
    )) as { profileImageURL?: unknown } | null;
    const profileImageURL =
      typeof row?.profileImageURL === "string"
        ? httpsURLValue(row.profileImageURL)
        : null;
    return { ...identity, picture: profileImageURL ?? identity.picture };
  } catch {
    return identity;
  }
});

export const getPendingAdmin = cache(async (): Promise<AdminIdentity | null> => {
  const token = (await cookies()).get(pendingCookieName)?.value;
  const payload = await verifyAdminToken(token, "pending");
  return payload ? identityFromPayload(payload) : null;
});

export async function requireAdminSession(): Promise<AdminIdentity> {
  const session = await getAdminSession();
  if (!session) {
    redirect("/login");
  }
  return session;
}

export async function requireAdminApiSession(): Promise<AdminIdentity | null> {
  return getAdminSession();
}

export function googleClientId(): string {
  return (
    process.env.GOOGLE_CLIENT_ID?.trim() ||
    process.env.GOOGLE_SERVER_CLIENT_ID?.trim() ||
    ""
  );
}

export function googleRedirectURI(request: Request): string {
  const configuredBaseURL = process.env.ADMIN_BASE_URL?.trim();
  const origin = configuredBaseURL
    ? new URL(configuredBaseURL).origin
    : new URL(request.url).origin;
  return `${origin}/api/auth/google/callback`;
}

export function verifyAdminPassword(password: string): boolean {
  const configuredPassword = requiredEnvironmentVariable("ADMIN_PASSWORD");
  const supplied = Buffer.from(createHash("sha256").update(password).digest());
  const expected = Buffer.from(
    createHash("sha256").update(configuredPassword).digest(),
  );
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}

export function authenticationConfiguration() {
  return {
    google: Boolean(googleClientId() && process.env.GOOGLE_CLIENT_SECRET?.trim()),
    allowlist: allowedAdminEmails().size > 0,
    password: Boolean(process.env.ADMIN_PASSWORD?.trim()),
    sessionSecret: Boolean(process.env.ADMIN_SESSION_SECRET?.trim()),
  };
}

export function assertSameOrigin(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return process.env.NODE_ENV !== "production";

  try {
    return new URL(origin).host === new URL(request.url).host;
  } catch {
    return false;
  }
}

function allowedAdminEmails(): Set<string> {
  const raw =
    process.env.ADMIN_ALLOWED_EMAILS?.trim() ||
    process.env.ADMIN_GOOGLE_EMAIL?.trim() ||
    "";
  return new Set(
    raw
      .split(",")
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
  );
}

async function signAdminToken(
  identity: AdminIdentity,
  purpose: AdminTokenPayload["purpose"],
  lifetimeSeconds: number,
) {
  return new SignJWT({ ...identity, purpose, role: "admin" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime(`${lifetimeSeconds}s`)
    .setJti(randomUUID())
    .sign(sessionSecret());
}

async function verifyAdminToken(
  token: string | undefined,
  purpose: AdminTokenPayload["purpose"],
): Promise<AdminTokenPayload | null> {
  if (!token) return null;

  try {
    const { payload } = await jwtVerify(token, sessionSecret(), {
      algorithms: ["HS256"],
    });
    if (
      payload.purpose !== purpose ||
      payload.role !== "admin" ||
      typeof payload.email !== "string" ||
      typeof payload.name !== "string"
    ) {
      return null;
    }
    return payload as AdminTokenPayload;
  } catch {
    return null;
  }
}

function sessionSecret(): Uint8Array {
  const secret = requiredEnvironmentVariable("ADMIN_SESSION_SECRET");
  if (secret.length < 32) {
    throw new Error("ADMIN_SESSION_SECRET must be at least 32 characters.");
  }
  return new TextEncoder().encode(secret);
}

function googleClientIdOrThrow(): string {
  const clientId = googleClientId();
  if (!clientId) throw new Error("Missing required environment variable: GOOGLE_CLIENT_ID");
  return clientId;
}

function safeEqual(value: string, expected: string) {
  const suppliedBuffer = Buffer.from(value);
  const expectedBuffer = Buffer.from(expected);
  return (
    suppliedBuffer.length === expectedBuffer.length &&
    timingSafeEqual(suppliedBuffer, expectedBuffer)
  );
}

function identityFromPayload(payload: AdminTokenPayload): AdminIdentity {
  return {
    email: payload.email,
    name: payload.name,
    picture: typeof payload.picture === "string" ? payload.picture : null,
  };
}

function cookieOptions(maxAge: number) {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax" as const,
    path: "/",
    maxAge,
    priority: "high" as const,
  };
}

function stringClaim(payload: JWTPayload, key: string): string | null {
  const value = payload[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function httpsURLClaim(payload: JWTPayload, key: string): string | null {
  const value = stringClaim(payload, key);
  if (!value) return null;

  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function httpsURLValue(value: string): string | null {
  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

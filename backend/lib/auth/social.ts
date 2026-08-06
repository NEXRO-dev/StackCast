import { createHash } from "node:crypto";
import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";

const googleKeys = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
);
const appleKeys = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys"),
);

export type VerifiedSocialIdentity = {
  subject: string;
  email: string | null;
  name: string | null;
  profileImageURL: string | null;
};

export async function verifyGoogleIdentityToken(
  identityToken: string,
): Promise<VerifiedSocialIdentity> {
  const audience = requiredEnvironmentVariable("GOOGLE_SERVER_CLIENT_ID");
  const { payload } = await jwtVerify(identityToken, googleKeys, {
    audience,
    issuer: ["https://accounts.google.com", "accounts.google.com"],
  });

  if (!payload.sub || payload.email_verified !== true) {
    throw new Error("Google token is missing a verified identity.");
  }

  return {
    subject: payload.sub,
    email: stringClaim(payload, "email"),
    name: stringClaim(payload, "name"),
    profileImageURL: httpsURLClaim(payload, "picture"),
  };
}

export async function verifyAppleIdentityToken(
  identityToken: string,
  rawNonce: string,
): Promise<VerifiedSocialIdentity> {
  const audience = process.env.APPLE_CLIENT_ID?.trim() || "com.nexro.Tsundoku";
  const { payload } = await jwtVerify(identityToken, appleKeys, {
    audience,
    issuer: "https://appleid.apple.com",
  });
  const expectedNonce = createHash("sha256").update(rawNonce).digest("hex");

  if (!payload.sub || payload.nonce !== expectedNonce) {
    throw new Error("Apple token nonce is invalid.");
  }

  return {
    subject: payload.sub,
    email: verifiedAppleEmail(payload),
    name: null,
    profileImageURL: null,
  };
}

function verifiedAppleEmail(payload: JWTPayload): string | null {
  const isVerified =
    payload.email_verified === true || payload.email_verified === "true";
  return isVerified ? stringClaim(payload, "email") : null;
}

function stringClaim(payload: JWTPayload, key: string): string | null {
  const value = payload[key];
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function httpsURLClaim(payload: JWTPayload, key: string): string | null {
  const value = stringClaim(payload, key);
  if (!value) {
    return null;
  }

  try {
    const url = new URL(value);
    return url.protocol === "https:" ? url.toString() : null;
  } catch {
    return null;
  }
}

function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

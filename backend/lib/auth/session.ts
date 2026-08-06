import { createHash, randomBytes, randomUUID } from "node:crypto";

const sessionLifetimeMilliseconds = 30 * 24 * 60 * 60 * 1000;

export type NewSession = {
  id: string;
  token: string;
  tokenHash: string;
  expiresAt: string;
  createdAt: string;
};

export function createSession(): NewSession {
  const token = randomBytes(32).toString("base64url");
  const createdAt = new Date().toISOString();

  return {
    id: randomUUID(),
    token,
    tokenHash: hashSessionToken(token),
    expiresAt: new Date(Date.now() + sessionLifetimeMilliseconds).toISOString(),
    createdAt,
  };
}

export function hashSessionToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function bearerToken(request: Request): string | null {
  const authorization = request.headers.get("authorization");

  if (!authorization?.startsWith("Bearer ")) {
    return null;
  }

  const token = authorization.slice("Bearer ".length).trim();
  return token || null;
}

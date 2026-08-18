import { bearerToken, hashSessionToken } from "./session";
import { getTurso } from "../turso";

export async function authenticatedUserID(request: Request): Promise<string | null> {
  const token = bearerToken(request);
  if (!token) return null;

  const session = (await getTurso().get(
    `SELECT user_id AS userID
     FROM auth_sessions
     WHERE token_hash = ? AND expires_at > ?
     LIMIT 1`,
    hashSessionToken(token),
    new Date().toISOString(),
  )) as { userID?: string } | null;

  return session?.userID ?? null;
}

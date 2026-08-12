import { randomBytes } from "node:crypto";
import { getTurso } from "@/lib/turso";

const shareTokenPattern = /^[A-Za-z0-9_-]{43}$/;

export type PublicCast = {
  id: string;
  title: string;
  summary: string | null;
  durationMinutes: number;
  language: string;
  audioObjectKey: string;
  createdAt: string;
  completedAt: string | null;
};

type ShareRow = PublicCast & { token: string };

export async function createOrGetCastShare(
  userID: string,
  castID: string,
): Promise<{ token: string }> {
  const database = getTurso();
  const cast = (await database.get(
    `SELECT id
     FROM casts
     WHERE id = ? AND user_id = ? AND status = 'completed'
       AND audio_object_key IS NOT NULL
     LIMIT 1`,
    castID,
    userID,
  )) as { id?: string } | null;

  if (!cast?.id) throw new Error("CAST_NOT_SHAREABLE");

  const existing = (await database.get(
    `SELECT token FROM cast_shares WHERE cast_id = ? LIMIT 1`,
    castID,
  )) as { token?: string } | null;
  if (existing?.token) return { token: existing.token };

  const token = randomBytes(32).toString("base64url");
  const now = new Date().toISOString();
  await database.run(
    `INSERT OR IGNORE INTO cast_shares (cast_id, token, created_at, updated_at)
     VALUES (?, ?, ?, ?)`,
    castID,
    token,
    now,
    now,
  );

  const stored = (await database.get(
    `SELECT token FROM cast_shares WHERE cast_id = ? LIMIT 1`,
    castID,
  )) as { token?: string } | null;
  if (!stored?.token) throw new Error("CAST_SHARE_CREATION_FAILED");
  return { token: stored.token };
}

export async function revokeCastShare(userID: string, castID: string): Promise<void> {
  const result = await getTurso().run(
    `DELETE FROM cast_shares
     WHERE cast_id = ?
       AND EXISTS (SELECT 1 FROM casts WHERE id = ? AND user_id = ?)`,
    castID,
    castID,
    userID,
  );
  if (result.changes !== 1) throw new Error("CAST_SHARE_NOT_FOUND");
}

export async function getPublicCastByToken(token: string): Promise<PublicCast | null> {
  if (!shareTokenPattern.test(token)) return null;

  const row = (await getTurso().get(
    `SELECT casts.id,
            casts.title,
            casts.summary,
            casts.duration_minutes AS durationMinutes,
            casts.language,
            casts.audio_object_key AS audioObjectKey,
            casts.created_at AS createdAt,
            casts.completed_at AS completedAt,
            cast_shares.token
     FROM cast_shares
     INNER JOIN casts ON casts.id = cast_shares.cast_id
     WHERE cast_shares.token = ?
       AND casts.status = 'completed'
       AND casts.audio_object_key IS NOT NULL
     LIMIT 1`,
    token,
  )) as ShareRow | null;

  if (!row) return null;
  return {
    id: row.id,
    title: row.title,
    summary: row.summary,
    durationMinutes: row.durationMinutes,
    language: row.language,
    audioObjectKey: row.audioObjectKey,
    createdAt: row.createdAt,
    completedAt: row.completedAt,
  };
}

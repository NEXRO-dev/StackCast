import { deleteR2Objects, listR2ObjectKeys } from "@/lib/r2-storage";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

/** Reconcile profile-image objects against the current DB references. */
export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const rows = await getTurso().all(
    `SELECT profile_image_object_key AS objectKey
     FROM user_profiles
     WHERE profile_image_object_key IS NOT NULL`,
  ) as Array<{ objectKey: string }>;
  const referencedKeys = new Set(rows.map((row) => row.objectKey));
  const storedKeys = await listR2ObjectKeys("profiles/");
  const orphanedKeys = storedKeys.filter((key) => !referencedKeys.has(key));
  const deleted = await deleteR2Objects(orphanedKeys);

  const deletedCasts = await getTurso().all(
    `SELECT id, audio_object_key AS audioObjectKey, artwork_object_key AS artworkObjectKey
     FROM casts
     WHERE deleted_at IS NOT NULL`,
  ) as Array<{ id: string; audioObjectKey: string | null; artworkObjectKey: string | null }>;
  const deletedCastObjects = deletedCasts.flatMap((cast) => [cast.audioObjectKey ?? "", cast.artworkObjectKey ?? ""]);
  const deletedCastObjectCount = await deleteR2Objects(deletedCastObjects);
  if (deletedCasts.length > 0) {
    await getTurso().batch(
      deletedCasts.map((cast) => ({ sql: "DELETE FROM casts WHERE id = ? AND deleted_at IS NOT NULL", args: [cast.id] })),
      "immediate",
    );
  }

  // Reconcile the whole Cast prefix as well, so objects left behind by an
  // older/manual DB deletion are removed even when no soft-delete row exists.
  const castRows = await getTurso().all(
    `SELECT audio_object_key AS audioObjectKey, artwork_object_key AS artworkObjectKey
     FROM casts`,
  ) as Array<{ audioObjectKey: string | null; artworkObjectKey: string | null }>;
  const referencedCastKeys = new Set(
    castRows.flatMap((cast) => [cast.audioObjectKey, cast.artworkObjectKey]).filter(
      (key): key is string => Boolean(key),
    ),
  );
  const storedCastKeys = await listR2ObjectKeys("casts/");
  const orphanedCastKeys = storedCastKeys.filter((key) => !referencedCastKeys.has(key));
  const deletedOrphanedCastObjects = await deleteR2Objects(orphanedCastKeys);

  console.info("[storage-cleanup] profile images reconciled", {
    stored: storedKeys.length,
    referenced: referencedKeys.size,
    deleted,
    deletedCasts: deletedCasts.length,
    deletedCastObjects: deletedCastObjectCount,
    deletedOrphanedCastObjects,
  });
  return Response.json({
    stored: storedKeys.length,
    referenced: referencedKeys.size,
    deleted,
    deletedCasts: deletedCasts.length,
    deletedCastObjects: deletedCastObjectCount,
    deletedOrphanedCastObjects,
  });
}

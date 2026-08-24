import { signedR2ObjectURL } from "@/lib/r2-storage";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function GET(
  _request: Request,
  context: { params: Promise<{ userID: string }> },
) {
  const { userID } = await context.params;
  const row = (await getTurso().get(
    `SELECT profile_image_object_key AS objectKey
     FROM user_profiles WHERE user_id = ? LIMIT 1`,
    userID,
  )) as { objectKey: string | null } | null;
  if (!row?.objectKey) return new Response(null, { status: 404 });
  return Response.redirect(await signedR2ObjectURL(row.objectKey), 302);
}

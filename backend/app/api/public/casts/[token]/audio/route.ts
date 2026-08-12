import { signedCastAudioURL } from "@/lib/cast/pipeline";
import { getPublicCastByToken } from "@/lib/cast/sharing";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  _request: Request,
  context: { params: Promise<{ token: string }> },
) {
  const { token } = await context.params;
  const cast = await getPublicCastByToken(token);
  if (!cast) return new Response("Not Found", { status: 404 });

  const signedURL = await signedCastAudioURL(cast.audioObjectKey);
  return Response.redirect(signedURL, 307);
}

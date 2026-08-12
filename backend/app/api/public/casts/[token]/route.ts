import { getPublicCastByToken } from "@/lib/cast/sharing";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(
  request: Request,
  context: { params: Promise<{ token: string }> },
) {
  const { token } = await context.params;
  const cast = await getPublicCastByToken(token);
  if (!cast) return Response.json({ error: { code: "not_found" } }, { status: 404 });

  const audioURL = new URL(`/api/public/casts/${token}/audio`, request.url).toString();
  return Response.json(
    {
      cast: {
        id: cast.id,
        title: cast.title,
        summary: cast.summary,
        transcript: null,
        durationMinutes: cast.durationMinutes,
        status: "completed",
        audioURL,
        creditCost: 0,
        errorMessage: null,
        createdAt: cast.createdAt,
        completedAt: cast.completedAt,
        shareToken: token,
      },
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}

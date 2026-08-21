import { processNextCastGenerationJob } from "@/lib/cast/pipeline";

export const runtime = "nodejs";
export const maxDuration = 300;

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const result = await processNextCastGenerationJob();
  console.info("[cast-worker] completed", result);
  return Response.json(result);
}

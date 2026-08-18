import { processNextDailyCast } from "@/lib/daily-news/cast-queue";
import { featureEnabled } from "@/lib/feature-flags";

export const runtime = "nodejs";
export const maxDuration = 300;

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET?.trim();
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  if (!featureEnabled("DAILY_CAST_ENABLED")) {
    return Response.json({ processed: false, skipped: "daily_cast_disabled" });
  }
  return Response.json(await processNextDailyCast());
}

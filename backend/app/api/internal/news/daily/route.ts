import { enqueueEligibleDailyCasts, processNextDailyCast } from "@/lib/daily-news/cast-queue";
import { featureEnabled } from "@/lib/feature-flags";
import { refreshSharedNewsPool } from "@/lib/news/refresh";
import { buildDailyEditionsForAllUsers, tokyoEditionDate } from "@/lib/recommendations/daily-edition";

export const runtime = "nodejs";
export const maxDuration = 300;

export async function GET(request: Request) {
  if (!isAuthorizedCron(request)) return Response.json({ error: "unauthorized" }, { status: 401 });
  if (!featureEnabled("PERSONAL_NEWS_ENABLED") || !featureEnabled("DAILY_NEWS_EDITION_ENABLED")) {
    return Response.json({ success: true, skipped: "daily_news_disabled" });
  }
  const editionDate = tokyoEditionDate();
  try {
    const provider = await refreshSharedNewsPool();
    const editions = await buildDailyEditionsForAllUsers(editionDate);
    const dailyCastEnabled = featureEnabled("DAILY_CAST_ENABLED");
    const queue = dailyCastEnabled ? await enqueueEligibleDailyCasts(editionDate) : { queued: 0, skipped: 0 };
    const processed = [];
    const inlineLimit = dailyCastEnabled
      ? Math.min(Math.max(Number(process.env.DAILY_CAST_INLINE_LIMIT ?? "3"), 0), 3)
      : 0;
    for (let index = 0; index < inlineLimit; index += 1) {
      const result = await processNextDailyCast();
      if (!result.processed) break;
      processed.push(result);
    }
    return Response.json({ success: true, editionDate, provider, editions, queue, processed });
  } catch (error) {
    console.error("Daily news cron failed", error);
    return Response.json({ success: false, error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}

function isAuthorizedCron(request: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim();
  return Boolean(secret && request.headers.get("authorization") === `Bearer ${secret}`);
}

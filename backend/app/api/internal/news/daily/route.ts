import { enqueueEligibleDailyCasts, processNextDailyCast } from "@/lib/daily-news/cast-queue";
import { featureEnabled } from "@/lib/feature-flags";
import { refreshSharedNewsPool } from "@/lib/news/refresh";
import { buildDailyEditionsForUsers, dueDailyEditionTargets } from "@/lib/recommendations/daily-edition";
import { randomUUID } from "node:crypto";

export const runtime = "nodejs";
export const maxDuration = 300;

export async function GET(request: Request) {
  const requestID = randomUUID();
  const startedAt = Date.now();
  console.info("[daily-news] cron request started", {
    requestID,
    authorizationConfigured: Boolean(process.env.CRON_SECRET?.trim()),
  });
  if (!isAuthorizedCron(request)) {
    console.warn("[daily-news] cron request rejected", { requestID, reason: "unauthorized" });
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  if (!featureEnabled("PERSONAL_NEWS_ENABLED") || !featureEnabled("DAILY_NEWS_EDITION_ENABLED")) {
    console.info("[daily-news] cron request skipped", { requestID, reason: "feature_disabled" });
    return Response.json({ success: true, skipped: "daily_news_disabled" });
  }
  try {
    const targets = await dueDailyEditionTargets();
    if (targets.length === 0) {
      console.info("[daily-news] cron request skipped", { requestID, reason: "no_users_due" });
      return Response.json({ success: true, skipped: "no_users_due" });
    }
    const localeGroups = new Map<string, { language: "japanese" | "english"; sourceCountry: string; topicIDs: Set<string> }>();
    for (const target of targets) {
      const key = `${target.language}:${target.sourceCountry}`;
      const group = localeGroups.get(key) ?? {
        language: target.language,
        sourceCountry: target.sourceCountry,
        topicIDs: new Set<string>(),
      };
      for (const topicID of target.topicIDs) group.topicIDs.add(topicID);
      localeGroups.set(key, group);
    }
    const providerResults = [];
    for (const group of localeGroups.values()) {
      providerResults.push(await refreshSharedNewsPool({
        language: group.language,
        sourceCountry: group.sourceCountry,
        topicIDs: [...group.topicIDs],
      }));
    }
    const provider = providerResults.reduce((summary, result) => ({
      topics: summary.topics + result.topics,
      fetched: summary.fetched + result.fetched,
      stored: summary.stored + result.stored,
      failures: [...summary.failures, ...result.failures],
    }), { topics: 0, fetched: 0, stored: 0, failures: [] as string[] });
    if (provider.fetched === 0 && provider.stored === 0 && provider.failures.length > 0) {
      console.warn("[daily-news] cron request skipped", {
        requestID,
        reason: "provider_unavailable",
        failureCount: provider.failures.length,
      });
      return Response.json({ success: false, error: "provider_unavailable", provider }, { status: 503 });
    }
    const editions = await buildDailyEditionsForUsers(targets);
    console.info("[daily-news] editions built", {
      requestID,
      targetCount: targets.length,
      timeZones: [...new Set(targets.map((target) => target.timeZone))],
      ...editions,
    });
    const dailyCastEnabled = featureEnabled("DAILY_CAST_ENABLED");
    const queue = dailyCastEnabled
      ? await Promise.all([...new Set(targets.map((target) => target.editionDate))].map((editionDate) =>
        enqueueEligibleDailyCasts(editionDate, targets.filter((target) => target.editionDate === editionDate).map((target) => target.userID))))
      : [];
    const queueSummary = queue.reduce((summary, item) => ({ queued: summary.queued + item.queued, skipped: summary.skipped + item.skipped }), { queued: 0, skipped: 0 });
    const processed = [];
    const inlineLimit = dailyCastEnabled
      ? Math.min(Math.max(Number(process.env.DAILY_CAST_INLINE_LIMIT ?? "3"), 0), 3)
      : 0;
    for (let index = 0; index < inlineLimit; index += 1) {
      const result = await processNextDailyCast();
      if (!result.processed) break;
      processed.push(result);
    }
    const result = { success: true, provider, editions, queue: queueSummary, processed };
    console.info("[daily-news] cron request completed", {
      requestID,
      provider: { topics: provider.topics, fetched: provider.fetched, stored: provider.stored, failures: provider.failures.length, localeGroups: localeGroups.size },
      editions,
      queue: queueSummary,
      processed: processed.length,
      elapsedMs: Date.now() - startedAt,
    });
    return Response.json(result);
  } catch (error) {
    console.error("[daily-news] cron request failed", {
      requestID,
      error: error instanceof Error ? error.message : String(error),
      elapsedMs: Date.now() - startedAt,
    });
    return Response.json({ success: false, error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}

function isAuthorizedCron(request: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim();
  return Boolean(secret && request.headers.get("authorization") === `Bearer ${secret}`);
}

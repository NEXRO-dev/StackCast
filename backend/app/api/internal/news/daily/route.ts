import { enqueueEligibleDailyCasts, processNextDailyCast } from "@/lib/daily-news/cast-queue";
import { featureEnabled } from "@/lib/feature-flags";
import {
  newsRefreshBuildDecision,
  newsRefreshProviderUnavailable,
  refreshSharedNewsPool,
  type NewsRefreshResult,
} from "@/lib/news/refresh";
import {
  buildDailyEditionsForUsers,
  dueDailyEditionTargets,
  type DailyEditionTarget,
} from "@/lib/recommendations/daily-edition";
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
    const localeGroups = new Map<string, {
      language: "japanese" | "english";
      sourceCountry: string;
      topicIDs: Set<string>;
      targets: DailyEditionTarget[];
    }>();
    for (const target of targets) {
      const key = `${target.language}:${target.sourceCountry}`;
      const group = localeGroups.get(key) ?? {
        language: target.language,
        sourceCountry: target.sourceCountry,
        topicIDs: new Set<string>(),
        targets: [],
      };
      for (const topicID of target.topicIDs) group.topicIDs.add(topicID);
      group.targets.push(target);
      localeGroups.set(key, group);
    }

    const providerResults: NewsRefreshResult[] = [];
    let providerUnavailable = false;
    let editions = { users: 0, ready: 0, failed: 0 };
    for (const [localeKey, group] of localeGroups) {
      const providerResult = await refreshSharedNewsPool({
        language: group.language,
        sourceCountry: group.sourceCountry,
        topicIDs: [...group.topicIDs],
      });
      providerResults.push(providerResult);
      const unavailableForGroup = newsRefreshProviderUnavailable(providerResult);
      providerUnavailable ||= unavailableForGroup;
      if (unavailableForGroup) {
        console.warn("[daily-news] providers unavailable; rebuilding editions from cache", {
          requestID,
          localeKey,
          failureCount: providerResult.failures.length,
          targetCount: group.targets.length,
        });
      }
      const groupEditions = await buildDailyEditionsForUsers(
        group.targets,
        newsRefreshBuildDecision(providerResult),
      );
      editions = {
        users: editions.users + groupEditions.users,
        ready: editions.ready + groupEditions.ready,
        failed: editions.failed + groupEditions.failed,
      };
    }
    const provider = providerResults.reduce((summary, result) => ({
      topics: summary.topics + result.topics,
      fetched: summary.fetched + result.fetched,
      stored: summary.stored + result.stored,
      failures: [...summary.failures, ...result.failures],
      cooldown: summary.cooldown && result.cooldown,
    }), { topics: 0, fetched: 0, stored: 0, failures: [] as string[], cooldown: providerResults.length > 0 });
    console.info("[daily-news] editions built", {
      requestID,
      targetCount: targets.length,
      timeZones: [...new Set(targets.map((target) => target.timeZone))],
      providerUnavailable,
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
    const result = { success: true, providerUnavailable, provider, editions, queue: queueSummary, processed };
    console.info("[daily-news] cron request completed", {
      requestID,
      provider: { topics: provider.topics, fetched: provider.fetched, stored: provider.stored, failures: provider.failures.length, localeGroups: localeGroups.size },
      providerUnavailable,
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

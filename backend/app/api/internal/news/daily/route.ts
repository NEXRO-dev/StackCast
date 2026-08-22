import { enqueueEligibleDailyCasts } from "@/lib/daily-news/cast-queue";
import { featureEnabled } from "@/lib/feature-flags";
import {
  newsRefreshProviderUnavailable,
  newsRefreshProviderUnderfilled,
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
    console.info("[daily-news] 日次ニュースの対象ユーザーを確認", {
      requestID,
      対象ユーザー数: targets.length,
      実行時刻_日本語: "各ユーザーの保存タイムゾーンにおける17:00〜17:59",
      対象ユーザー_日本語: targets.map((target) => ({
        userID: target.userID,
        timeZone: target.timeZone,
        editionDate: target.editionDate,
        language: target.language === "japanese" ? "日本語" : "英語",
        sourceCountry: target.sourceCountry,
        topicIDs: target.topicIDs,
      })),
    });
    if (targets.length === 0) {
      console.info("[daily-news] cron request skipped", {
        requestID,
        reason: "no_users_due",
        説明_日本語: "現在のCron実行時刻は対象ユーザーの17:00〜17:59実行枠外、または今日の定期版が処理済みです。",
      });
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
    let providerUnderfilled = false;
    let editions = { users: 0, ready: 0, failed: 0 };
    for (const [localeKey, group] of localeGroups) {
      const providerResult = await refreshSharedNewsPool({
        language: group.language,
        sourceCountry: group.sourceCountry,
        topicIDs: [...group.topicIDs],
        force: true,
      });
      console.info("[daily-news] ロケールグループの取得結果", {
        requestID,
        localeKey,
        対象ユーザー数: group.targets.length,
        成功取得数: providerResult.fetched,
        DB保存数: providerResult.stored,
        失敗数: providerResult.failures.length,
        説明_日本語: providerResult.stored >= 5
          ? "この言語・地域グループでは5件以上を確保しました。"
          : "5件未満のため、既存DBキャッシュを使ったfallback版を生成します。",
      });
      providerResults.push(providerResult);
      const unavailableForGroup = newsRefreshProviderUnavailable(providerResult);
      const underfilledForGroup = newsRefreshProviderUnderfilled(providerResult);
      providerUnavailable ||= unavailableForGroup;
      providerUnderfilled ||= underfilledForGroup;
      if (unavailableForGroup) {
        console.warn("[daily-news] providers unavailable; rebuilding editions from cache", {
          requestID,
          localeKey,
          failureCount: providerResult.failures.length,
          targetCount: group.targets.length,
        });
      }
      if (underfilledForGroup) {
        console.warn("[daily-news] providers underfilled; rebuilding editions with cached articles", {
          requestID,
          localeKey,
          stored: providerResult.stored,
          targetCount: group.targets.length,
        });
      }
      const groupEditions = await buildDailyEditionsForUsers(
        group.targets,
        {
          forceRebuild: true,
          markFallback: providerResult.stored < 5,
        },
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
      providerUnderfilled,
      ...editions,
    });
    const dailyCastEnabled = featureEnabled("DAILY_CAST_ENABLED");
    const queue = dailyCastEnabled
      ? await Promise.all([...new Set(targets.map((target) => target.editionDate))].map((editionDate) =>
        enqueueEligibleDailyCasts(editionDate, targets.filter((target) => target.editionDate === editionDate).map((target) => target.userID))))
      : [];
    const queueSummary = queue.reduce((summary, item) => ({ queued: summary.queued + item.queued, skipped: summary.skipped + item.skipped }), { queued: 0, skipped: 0 });
    const processed: Array<never> = [];
    const result = { success: true, providerUnavailable, providerUnderfilled, provider, editions, queue: queueSummary, processed };
    console.info("[daily-news] cron request completed", {
      requestID,
      provider: { topics: provider.topics, fetched: provider.fetched, stored: provider.stored, failures: provider.failures.length, localeGroups: localeGroups.size },
      providerUnavailable,
      providerUnderfilled,
      editions,
      queue: queueSummary,
      processed: processed.length,
      AI処理_日本語: "このcronではDaily Castを直接生成せず、queue投入のみ行います。別workerが1回1件ずつ処理します。",
      elapsedMs: Date.now() - startedAt,
    });
    return Response.json(result);
  } catch (error) {
    console.error("[daily-news] cron request failed", {
      requestID,
      error: error instanceof Error ? error.message : String(error),
      原因_日本語: "日次ニュース処理の途中で、データベース・設定・外部プロバイダーのいずれかが失敗しました。",
      対応_日本語: "この実行は500で終了しました。次の5分間隔Cronで再実行されます。",
      elapsedMs: Date.now() - startedAt,
    });
    return Response.json({ success: false, error: error instanceof Error ? error.message : String(error) }, { status: 500 });
  }
}

function isAuthorizedCron(request: Request): boolean {
  const secret = process.env.CRON_SECRET?.trim();
  return Boolean(secret && request.headers.get("authorization") === `Bearer ${secret}`);
}

import { randomUUID } from "node:crypto";
import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { featureEnabled } from "@/lib/feature-flags";
import { refreshSharedNewsPool } from "@/lib/news/refresh";
import { newsLocaleForUser } from "@/lib/news/user-locale";
import { buildDailyEdition, dailyEditionDateForUser, dailyEditionForUser } from "@/lib/recommendations/daily-edition";

export const runtime = "nodejs";
export const maxDuration = 120;

type ProviderSummary = { topics: number; fetched: number; stored: number; failures: string[] };
type RefreshJob = { status: "queued" | "running" | "completed" | "failed"; error?: string };
const refreshJobs = new Map<string, RefreshJob>();
const activeRefreshByUser = new Map<string, string>();

/** Development-only refresh trigger. The response is DB-first and never waits for providers. */
export async function POST(request: Request) {
  const requestID = randomUUID();
  if (!featureEnabled("PERSONAL_NEWS_ENABLED")) {
    return errorResponse("feature_disabled", "Personal news is currently unavailable.", 503);
  }
  if (process.env.NODE_ENV === "production" && process.env.DEBUG_DAILY_NEWS_ENABLED !== "true") {
    return errorResponse("feature_disabled", "Debug news refresh is disabled.", 503);
  }

  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  try {
    const editionDate = await dailyEditionDateForUser(userID);
    const edition = await dailyEditionForUser(userID, editionDate);
    const activeRequestID = activeRefreshByUser.get(userID);
    if (activeRequestID) {
      console.info("[daily-news] debug refresh skipped", {
        reason: "already_running",
        userID,
        requestID: activeRequestID,
      });
      return Response.json({
        ...feedPayload(edition, editionDate),
        refreshing: true,
        refreshRequestID: activeRequestID,
      });
    }
    refreshJobs.set(requestID, { status: "queued" });
    activeRefreshByUser.set(userID, requestID);
    void refreshInBackground(userID, requestID, editionDate);
    console.info("[daily-news] debug refresh queued", {
      requestID,
      userID,
      editionDate,
      cachedItemCount: edition.items.length,
    });
    return Response.json({
      ...feedPayload(edition, editionDate),
      refreshing: true,
      refreshRequestID: requestID,
    });
  } catch (error) {
    console.error("[daily-news] debug refresh could not load cached feed", {
      requestID,
      userID,
      error: error instanceof Error ? error.message : String(error),
    });
    return errorResponse("feed_unavailable", "Unable to load the cached news feed.", 503);
  }
}

export async function GET(request: Request) {
  if (!featureEnabled("PERSONAL_NEWS_ENABLED")) {
    return errorResponse("feature_disabled", "Personal news is currently unavailable.", 503);
  }
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  const requestID = new URL(request.url).searchParams.get("requestID");
  if (!requestID) return errorResponse("invalid_request", "requestID is required.", 400);
  return Response.json(refreshJobs.get(requestID) ?? { status: "unknown" }, {
    status: refreshJobs.has(requestID) ? 200 : 404,
  });
}

async function refreshInBackground(userID: string, requestID: string, editionDate: string): Promise<void> {
  const startedAt = Date.now();
  refreshJobs.set(requestID, { status: "running" });
  try {
    const locale = await newsLocaleForUser(userID);
    const primary = await refreshSharedNewsPool({
      language: locale.language,
      sourceCountry: locale.sourceCountry,
      topicIDs: locale.topicIDs,
    });
    if (primary.fetched === 0 && primary.stored === 0 && primary.failures.length > 0) {
      console.warn("[daily-news] debug background refresh unavailable", {
        requestID,
        userID,
        failureCount: primary.failures.length,
        elapsedMs: Date.now() - startedAt,
      });
      refreshJobs.set(requestID, { status: "failed", error: "provider_unavailable" });
      return;
    }

    let provider: ProviderSummary = primary;
    if (primary.fetched > 0 && primary.stored === 0 && locale.topicIDs.length > 0) {
      const fallback = await refreshSharedNewsPool({
        language: locale.language,
        sourceCountry: locale.sourceCountry,
        excludeTopicIDs: locale.topicIDs,
      });
      provider = combineProviderResults(primary, fallback);
    }

    await buildDailyEdition(userID, editionDate, true);
    const edition = await dailyEditionForUser(userID, editionDate);
    console.info("[daily-news] debug background refresh completed", {
      requestID,
      userID,
      editionDate,
      itemCount: edition.items.length,
      provider: { topics: provider.topics, fetched: provider.fetched, stored: provider.stored },
      elapsedMs: Date.now() - startedAt,
    });
    refreshJobs.set(requestID, { status: "completed" });
  } catch (error) {
    console.error("[daily-news] debug background refresh failed", {
      requestID,
      userID,
      error: error instanceof Error ? error.message : String(error),
      elapsedMs: Date.now() - startedAt,
    });
    refreshJobs.set(requestID, {
      status: "failed",
      error: error instanceof Error ? error.message : String(error),
    });
  } finally {
    if (activeRefreshByUser.get(userID) === requestID) {
      activeRefreshByUser.delete(userID);
    }
  }
}

function combineProviderResults(primary: ProviderSummary, fallback: ProviderSummary): ProviderSummary {
  return {
    topics: primary.topics + fallback.topics,
    fetched: primary.fetched + fallback.fetched,
    stored: primary.stored + fallback.stored,
    failures: [...primary.failures, ...fallback.failures],
  };
}

function feedPayload(edition: Awaited<ReturnType<typeof dailyEditionForUser>>, editionDate: string) {
  return {
    feedId: edition.id,
    editionDate,
    status: edition.status,
    isFallback: edition.status === "fallback",
    generatedAt: edition.generatedAt,
    items: edition.items.slice(0, 5).map((item) => ({
      article: {
        id: item.id,
        url: item.url,
        title: item.title,
        description: item.description,
        imageURL: item.imageURL,
        source: item.source,
        publishedAt: item.publishedAt,
      },
      topicIDs: item.topicIDs,
      reason: item.reason,
      reasonEN: item.reasonEN,
      rank: item.rank,
    })),
    dailyCast: { status: edition.autoCastStatus, castId: edition.castID },
  };
}

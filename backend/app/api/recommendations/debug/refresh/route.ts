import { randomUUID } from "node:crypto";
import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { featureEnabled } from "@/lib/feature-flags";
import { newsRefreshProviderUnavailable, newsRefreshProviderUnderfilled, refreshSharedNewsPool } from "@/lib/news/refresh";
import { newsLocaleForUser } from "@/lib/news/user-locale";
import { buildDailyEdition, dailyEditionDateForUser, dailyEditionForUser } from "@/lib/recommendations/daily-edition";

export const runtime = "nodejs";
export const maxDuration = 180;

/** Development-only refresh trigger. Provider work completes before the response is returned. */
export async function POST(request: Request) {
  const requestID = randomUUID();
  const startedAt = Date.now();
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
    const locale = await newsLocaleForUser(userID);
    const provider = await refreshSharedNewsPool({
      language: locale.language,
      sourceCountry: locale.sourceCountry,
      topicIDs: locale.topicIDs,
      force: true,
    });
    const providerUnavailable = newsRefreshProviderUnavailable(provider);
    const providerUnderfilled = newsRefreshProviderUnderfilled(provider);
    await buildDailyEdition(userID, editionDate, {
      forceRebuild: true,
      markFallback: providerUnavailable || providerUnderfilled,
    });
    const edition = await dailyEditionForUser(userID, editionDate);
    console.info("[daily-news] debug refresh completed", {
      requestID,
      userID,
      editionDate,
      itemCount: edition.items.length,
      providerUnavailable,
      providerUnderfilled,
      provider: { topics: provider.topics, fetched: provider.fetched, stored: provider.stored },
      elapsedMs: Date.now() - startedAt,
    });
    return Response.json({
      ...feedPayload(edition, editionDate),
      refreshing: false,
      refreshRequestID: requestID,
      ...(providerUnavailable ? { refreshError: "provider_unavailable" } : {}),
      ...(!providerUnavailable && providerUnderfilled ? { refreshError: "provider_underfilled" } : {}),
    });
  } catch (error) {
    console.error("[daily-news] debug refresh failed", {
      requestID,
      userID,
      error: error instanceof Error ? error.message : String(error),
      elapsedMs: Date.now() - startedAt,
    });
    return errorResponse("feed_unavailable", "Unable to refresh the news feed.", 503);
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
  return Response.json({
    status: "completed",
    synchronous: true,
    requestID,
  });
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

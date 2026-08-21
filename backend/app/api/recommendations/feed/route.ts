import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { featureEnabled } from "@/lib/feature-flags";
import { dailyEditionDateForUser, dailyEditionForUser } from "@/lib/recommendations/daily-edition";

export const runtime = "nodejs";

export async function GET(request: Request) {
  if (!featureEnabled("PERSONAL_NEWS_ENABLED")) {
    return errorResponse("feature_disabled", "Personal news is currently unavailable.", 503);
  }
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  const requestedDate = new URL(request.url).searchParams.get("date");
  const editionDate = requestedDate && /^\d{4}-\d{2}-\d{2}$/.test(requestedDate)
    ? requestedDate
    : await dailyEditionDateForUser(userID);
  try {
    const edition = await dailyEditionForUser(userID, editionDate);
    return Response.json({
      feedId: edition.id,
      editionDate,
      status: edition.status,
      isFallback: edition.status === "fallback",
      generatedAt: edition.generatedAt,
      items: edition.items.map((item) => ({
        article: {
          id: item.id, url: item.url, title: item.title, description: item.description,
          imageURL: item.imageURL, source: item.source, publishedAt: item.publishedAt,
        },
        topicIDs: item.topicIDs,
        reason: item.reason,
        reasonEN: item.reasonEN,
        rank: item.rank,
      })),
      dailyCast: { status: edition.autoCastStatus, castId: edition.castID },
    });
  } catch (error) {
    console.error("Recommendation feed failed", error);
    return errorResponse("feed_unavailable", "Unable to load today's news.", 503);
  }
}

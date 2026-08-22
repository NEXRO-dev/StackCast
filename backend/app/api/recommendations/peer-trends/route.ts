import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { effectiveSubscriptionForUser } from "@/lib/billing/effective-plan";
import { errorResponse } from "@/lib/auth/response";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

const MINIMUM_COHORT_SIZE = 10;
const LOOKBACK_DAYS = 30;

export async function GET(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);

  try {
    const database = getTurso();
    const profile = (await database.get(
      "SELECT age_band AS ageBand FROM user_recommendation_profiles WHERE user_id = ? LIMIT 1",
      userID,
    )) as { ageBand?: string } | null;
    const ageBand = profile?.ageBand;
    const subscription = await effectiveSubscriptionForUser(database, userID);
    const isPaid = subscription.effectivePlanTier === "plus" || subscription.effectivePlanTier === "pro";

    if (!ageBand || ageBand === "unspecified") {
      return Response.json({ available: false, locked: !isPaid, reason: "age_not_set", participantCount: 0, topics: [], articles: [] });
    }

    const since = new Date(Date.now() - LOOKBACK_DAYS * 24 * 60 * 60 * 1000).toISOString();
    const participant = (await database.get(
      `SELECT COUNT(DISTINCT p.user_id) AS participantCount
       FROM user_recommendation_profiles p
       JOIN users u ON u.id = p.user_id
       WHERE p.age_band = ? AND p.onboarding_completed_at IS NOT NULL AND p.user_id != ?`,
      ageBand,
      userID,
    )) as { participantCount?: number } | null;
    const participantCount = Number(participant?.participantCount ?? 0);

    if (participantCount < MINIMUM_COHORT_SIZE) {
      return Response.json({
        available: false,
        locked: !isPaid,
        reason: "insufficient_cohort",
        participantCount: 0,
        topics: [],
        articles: [],
      });
    }

    if (!isPaid) {
      return Response.json({ available: true, locked: true, participantCount, topics: [], articles: [] });
    }

    const topics = await database.all(
      `SELECT t.id, t.name_ja AS nameJA, t.name_en AS nameEN,
              COUNT(DISTINCT e.user_id) AS readerCount
       FROM recommendation_events e
       JOIN user_recommendation_profiles p ON p.user_id = e.user_id
       JOIN news_article_topics at ON at.article_id = e.article_id
       JOIN recommendation_topics t ON t.id = at.topic_id
       WHERE p.age_band = ? AND e.user_id != ? AND e.occurred_at >= ?
         AND e.event_type IN ('impression', 'open', 'dwell', 'save', 'add_to_cast', 'cast_completed')
       GROUP BY t.id, t.name_ja, t.name_en
       ORDER BY readerCount DESC, t.sort_order ASC
       LIMIT 3`,
      ageBand,
      userID,
      since,
    ) as Array<{ id: string; nameJA: string; nameEN: string; readerCount: number }>;

    const articles = await database.all(
      `SELECT a.id, a.title, a.source_domain AS sourceDomain, a.image_url AS imageURL,
              a.original_url AS originalURL, COUNT(DISTINCT e.user_id) AS readerCount
       FROM recommendation_events e
       JOIN user_recommendation_profiles p ON p.user_id = e.user_id
       JOIN news_articles a ON a.id = e.article_id
       WHERE p.age_band = ? AND e.user_id != ? AND e.occurred_at >= ?
         AND e.event_type IN ('open', 'dwell', 'save', 'add_to_cast', 'cast_completed')
       GROUP BY a.id, a.title, a.source_domain, a.image_url, a.original_url
       ORDER BY readerCount DESC, a.published_at DESC
       LIMIT 3`,
      ageBand,
      userID,
      since,
    ) as Array<{ id: string; title: string; sourceDomain: string; imageURL: string | null; originalURL: string; readerCount: number }>;

    return Response.json({ available: topics.length > 0 || articles.length > 0, locked: false, participantCount, topics, articles });
  } catch (error) {
    console.error("Peer trends lookup failed", error);
    return errorResponse("server_error", "Unable to load peer trends.", 500);
  }
}

import { randomUUID } from "node:crypto";
import { effectiveSubscriptionForUser } from "../billing/effective-plan";
import { createCast } from "../cast/pipeline";
import { getTurso } from "../turso";
import { tokyoEditionDate } from "../recommendations/daily-edition";

type EligibleRow = {
  editionID: string;
  userID: string;
  durationMinutes: number;
  consentAt: string | null;
  enabled: number;
  lastActiveAt: string | null;
};

export async function enqueueEligibleDailyCasts(editionDate = tokyoEditionDate(), userIDs?: string[]): Promise<{ queued: number; skipped: number }> {
  const userFilter = userIDs?.length ? ` AND e.user_id IN (${userIDs.map(() => "?").join(", ")})` : "";
  const args: Array<string> = [editionDate, ...(userIDs ?? [])];
  const rows = (await getTurso().all(
    `SELECT e.id AS editionID, e.user_id AS userID,
            p.daily_cast_duration_minutes AS durationMinutes,
            p.ai_processing_consent_at AS consentAt,
            p.daily_auto_cast_enabled AS enabled,
            (SELECT MAX(last_used_at) FROM auth_sessions s WHERE s.user_id = e.user_id) AS lastActiveAt
     FROM daily_news_editions e
     LEFT JOIN user_recommendation_profiles p ON p.user_id = e.user_id
     WHERE e.edition_date = ? AND e.status IN ('ready', 'fallback')${userFilter}`,
    ...args,
  )) as EligibleRow[];
  let queued = 0;
  let skipped = 0;
  const sevenDaysAgo = Date.now() - 7 * 24 * 60 * 60 * 1000;

  for (const row of rows) {
    let reason: string | null = null;
    const subscription = await effectiveSubscriptionForUser(getTurso(), row.userID);
    if (subscription.effectivePlanTier !== "plus" && subscription.effectivePlanTier !== "pro") reason = "plan_not_eligible";
    else if (!row.enabled) reason = "auto_cast_disabled";
    else if (!row.consentAt) reason = "ai_consent_required";
    else if (!row.lastActiveAt || Date.parse(row.lastActiveAt) < sevenDaysAgo) reason = "inactive_user";

    if (reason) {
      await getTurso().run(
        "UPDATE daily_news_editions SET auto_cast_status = 'skipped', skip_reason = ?, updated_at = ? WHERE id = ?",
        reason, new Date().toISOString(), row.editionID,
      );
      skipped += 1;
      continue;
    }

    const now = new Date().toISOString();
    const result = await getTurso().run(
      `INSERT OR IGNORE INTO daily_cast_jobs
        (id, edition_id, user_id, status, stage, attempt_count, created_at, updated_at)
       VALUES (?, ?, ?, 'queued', 'fetch', 0, ?, ?)`,
      randomUUID(), row.editionID, row.userID, now, now,
    );
    if (result.changes === 1) {
      await getTurso().run(
        "UPDATE daily_news_editions SET auto_cast_status = 'queued', skip_reason = NULL, updated_at = ? WHERE id = ?",
        now, row.editionID,
      );
      queued += 1;
    }
  }
  return { queued, skipped };
}

export async function processNextDailyCast(): Promise<{ processed: boolean; jobID?: string; castID?: string; error?: string }> {
  const database = getTurso();
  const now = new Date();
  const row = (await database.get(
    `SELECT j.id AS jobID, j.edition_id AS editionID, j.user_id AS userID,
            p.daily_cast_duration_minutes AS durationMinutes, u.preferred_language AS language
     FROM daily_cast_jobs j
     JOIN users u ON u.id = j.user_id
     LEFT JOIN user_recommendation_profiles p ON p.user_id = j.user_id
     WHERE j.status IN ('queued', 'retry_wait')
       AND (j.next_attempt_at IS NULL OR j.next_attempt_at <= ?)
       AND (j.lease_until IS NULL OR j.lease_until < ?)
     ORDER BY j.created_at LIMIT 1`,
    now.toISOString(), now.toISOString(),
  )) as { jobID?: string; editionID?: string; userID?: string; durationMinutes?: number; language?: string } | null;
  if (!row?.jobID || !row.editionID || !row.userID) return { processed: false };

  const leaseUntil = new Date(now.getTime() + 10 * 60 * 1000).toISOString();
  const claimed = await database.run(
    `UPDATE daily_cast_jobs SET status = 'processing', stage = 'fetch', lease_until = ?,
       attempt_count = attempt_count + 1, updated_at = ?
     WHERE id = ? AND status IN ('queued', 'retry_wait')`,
    leaseUntil, now.toISOString(), row.jobID,
  );
  if (claimed.changes !== 1) return { processed: false };
  await database.run("UPDATE daily_news_editions SET auto_cast_status = 'processing', updated_at = ? WHERE id = ?", now.toISOString(), row.editionID);

  const sources = (await database.all(
    `SELECT a.original_url AS url, a.title
     FROM daily_news_edition_items i JOIN news_articles a ON a.id = i.article_id
     WHERE i.edition_id = ? ORDER BY i.rank`,
    row.editionID,
  )) as Array<{ url: string; title: string }>;
  try {
    if (sources.length !== 5) throw new Error("DAILY_CAST_REQUIRES_FIVE_ARTICLES");
    const title = row.language === "english" ? "Today's News in 5" : "今日のニュース5選";
    const cast = await createCast(row.userID, {
      title,
      durationMinutes: normalizeDuration(row.durationMinutes),
      sources,
      internalKind: "daily_news",
    });
    const completedAt = new Date().toISOString();
    await database.batch([
      { sql: "UPDATE daily_cast_jobs SET status = 'completed', stage = 'persist', cast_id = ?, lease_until = NULL, error_code = NULL, updated_at = ? WHERE id = ?", args: [cast.id, completedAt, row.jobID] },
      { sql: "UPDATE daily_news_editions SET cast_id = ?, auto_cast_status = 'ready', skip_reason = NULL, updated_at = ? WHERE id = ?", args: [cast.id, completedAt, row.editionID] },
    ], "immediate");
    return { processed: true, jobID: row.jobID, castID: cast.id };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const job = (await database.get("SELECT attempt_count AS attempts FROM daily_cast_jobs WHERE id = ?", row.jobID)) as { attempts?: number } | null;
    const terminal = (job?.attempts ?? 1) >= 3 || message === "CAST_INSUFFICIENT_CREDITS";
    const retryAt = new Date(Date.now() + 15 * 60 * 1000).toISOString();
    await database.batch([
      { sql: "UPDATE daily_cast_jobs SET status = ?, next_attempt_at = ?, lease_until = NULL, error_code = ?, updated_at = ? WHERE id = ?", args: [terminal ? "failed" : "retry_wait", terminal ? null : retryAt, message.slice(0, 180), new Date().toISOString(), row.jobID] },
      { sql: "UPDATE daily_news_editions SET auto_cast_status = ?, skip_reason = ?, updated_at = ? WHERE id = ?", args: [terminal ? "failed" : "queued", message.slice(0, 180), new Date().toISOString(), row.editionID] },
    ], "immediate");
    return { processed: true, jobID: row.jobID, error: message };
  }
}

function normalizeDuration(value?: number): number {
  return typeof value === "number" && Number.isInteger(value) && value >= 5 && value <= 20 ? value : 5;
}

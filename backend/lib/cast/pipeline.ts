import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { createHash, randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { getTurso } from "@/lib/turso";
import { effectiveSubscriptionForUser } from "@/lib/billing/effective-plan";
import { sendUserPush } from "@/lib/notifications/push";
import { buildCastGenerationPrompt, buildFishAudioInput, castSafetyPolicy, type CastLanguage } from "./prompt";

const openAIModel = "gpt-5.6-luna";
const fishAudioEndpoint = "https://api.fish.audio/v1/tts";
// Use the paid-plan model for production/commercial use. The free promotional
// model has an explicit end date and no production SLA.
const fishAudioModel = "s1";
const maxSourceCharacters = 30_000;
const signedURLLifetimeSeconds = 60 * 60;

export type CastSourceInput = {
  url: string;
  title?: string;
  text?: string;
};

export type CreateCastInput = {
  title?: string;
  durationMinutes?: number;
  sources: CastSourceInput[];
  internalKind?: "daily_news";
};

type GeneratedCastContent = {
  title: string;
  script: string;
};

export type CastRecord = {
  id: string;
  title: string;
  summary: string | null;
  transcript: string | null;
  durationMinutes: number;
  status: "queued" | "processing" | "completed" | "failed";
  progressPercent: number;
  audioObjectKey: string | null;
  audioURL?: string | null;
  artworkObjectKey: string | null;
  artworkURL?: string | null;
  creditCost: number;
  errorMessage: string | null;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
  shareToken?: string | null;
};

type CastRow = {
  id: string;
  title: string;
  summary: string | null;
  transcript: string | null;
  durationMinutes: number;
  status: CastRecord["status"];
  progressPercent: number;
  audioObjectKey: string | null;
  artworkObjectKey: string | null;
  creditCost: number;
  errorMessage: string | null;
  createdAt: string;
  updatedAt: string;
  completedAt: string | null;
  shareToken?: string | null;
};

let r2Client: S3Client | undefined;

function logCastEvent(event: string, details: Record<string, unknown> = {}): void {
  console.info(`[cast] ${event}`, { at: new Date().toISOString(), ...details });
}

const creditLimits: Record<string, number> = {
  // Free is limited to 10-minute Casts. A 10-minute Cast costs 2 credits,
  // so 6 credits matches the advertised monthly limit of 3 Casts.
  free: 6,
  plus: 40,
  pro: 100,
  lifetime: 150,
};

async function reserveCredits(userID: string, castID: string, amount: number, now: string): Promise<void> {
  const database = getTurso();
  const planTier = await currentPlanTier(userID);
  const isLifetime = planTier === "lifetime";
  const periodStart = isLifetime ? "lifetime" : monthStart(now);
  const periodEnd = isLifetime ? "9999-12-31T23:59:59.999Z" : nextMonthStart(now);
  const periodID = `${userID}:${periodStart}`;
  const limit = creditLimits[planTier] ?? creditLimits.free;

  const before = (await database.get(
    `SELECT credit_limit AS creditLimit,
            credits_reserved AS creditsReserved,
            credits_used AS creditsUsed
     FROM user_credit_periods
     WHERE id = ? LIMIT 1`,
    periodID,
  )) as { creditLimit?: number; creditsReserved?: number; creditsUsed?: number } | null;
  logCastEvent("credits reservation requested", {
    userID,
    castID,
    planTier,
    amount,
    periodID,
    creditLimit: before?.creditLimit ?? limit,
    creditsReserved: before?.creditsReserved ?? 0,
    creditsUsed: before?.creditsUsed ?? 0,
  });

  await database.run(
    `INSERT INTO user_credit_periods
      (id, user_id, period_start, period_end, plan_tier, credit_limit,
       credits_reserved, credits_used, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
     ON CONFLICT (user_id, period_start, period_end) DO UPDATE SET
       plan_tier = excluded.plan_tier,
       credit_limit = excluded.credit_limit,
       updated_at = excluded.updated_at`,
    periodID,
    userID,
    periodStart,
    periodEnd,
    planTier,
    limit,
    now,
    now,
  );

  const result = await database.run(
    `UPDATE user_credit_periods
     SET credits_reserved = credits_reserved + ?, updated_at = ?
     WHERE id = ?
       AND credits_used + credits_reserved + ? <= credit_limit`,
    amount,
    now,
    periodID,
    amount,
  );

  const afterAttempt = (await database.get(
    `SELECT credit_limit AS creditLimit,
            credits_reserved AS creditsReserved,
            credits_used AS creditsUsed
     FROM user_credit_periods
     WHERE id = ? LIMIT 1`,
    periodID,
  )) as { creditLimit?: number; creditsReserved?: number; creditsUsed?: number } | null;
  logCastEvent("credits reservation SQL completed", {
    userID,
    castID,
    periodID,
    changes: result.changes,
    creditLimit: afterAttempt?.creditLimit ?? null,
    creditsReserved: afterAttempt?.creditsReserved ?? null,
    creditsUsed: afterAttempt?.creditsUsed ?? null,
    requestedAmount: amount,
  });

  if (result.changes !== 1) {
    logCastEvent("credits reservation denied", { userID, castID, planTier, amount, limit });
    throw new Error("CAST_INSUFFICIENT_CREDITS");
  }

  try {
    await database.run(
      `INSERT INTO cast_credit_ledger
        (id, user_id, cast_id, credit_period_id, amount, entry_type, idempotency_key, note, created_at)
       VALUES (?, ?, ?, ?, ?, 'reserve', ?, ?, ?)`,
      randomUUID(),
      userID,
      castID,
      periodID,
      amount,
      `reserve:${castID}`,
      `${planTier} plan reservation`,
      now,
    );
    logCastEvent("credits reserved", { userID, castID, amount, periodID });
  } catch (error) {
    console.error("[cast] credit ledger reservation failed", {
      userID,
      castID,
      amount,
      message: error instanceof Error ? error.message : String(error),
    });
    await database.run(
      `UPDATE user_credit_periods
       SET credits_reserved = MAX(0, credits_reserved - ?), updated_at = ?
       WHERE id = ?`,
      amount,
      new Date().toISOString(),
      periodID,
    );
    throw error;
  }
}

async function consumeCredits(userID: string, castID: string, amount: number, now: string): Promise<void> {
  const database = getTurso();
  const ledger = (await database.get(
    `SELECT credit_period_id AS creditPeriodID
     FROM cast_credit_ledger
     WHERE cast_id = ? AND user_id = ? AND entry_type = 'reserve'
     LIMIT 1`,
    castID,
    userID,
  )) as { creditPeriodID?: string } | null;
  if (!ledger?.creditPeriodID) throw new Error("CAST_CREDIT_RESERVATION_MISSING");

  await database.batch(
    [
      {
        sql: `UPDATE user_credit_periods
              SET credits_reserved = MAX(0, credits_reserved - ?),
                  credits_used = credits_used + ?, updated_at = ?
              WHERE id = ?`,
        args: [amount, amount, now, ledger.creditPeriodID],
      },
      {
        sql: `INSERT INTO cast_credit_ledger
              (id, user_id, cast_id, credit_period_id, amount, entry_type, idempotency_key, note, created_at)
              VALUES (?, ?, ?, ?, ?, 'consume', ?, 'Cast generation completed', ?)`,
        args: [randomUUID(), userID, castID, ledger.creditPeriodID, amount, `consume:${castID}`, now],
      },
    ],
    "immediate",
  );
  const afterConsume = (await database.get(
    `SELECT credits_reserved AS creditsReserved, credits_used AS creditsUsed
     FROM user_credit_periods WHERE id = ? LIMIT 1`,
    ledger.creditPeriodID,
  )) as { creditsReserved?: number; creditsUsed?: number } | null;
  logCastEvent("credits consumed", {
    userID,
    castID,
    amount,
    periodID: ledger.creditPeriodID,
    creditsReserved: afterConsume?.creditsReserved ?? null,
    creditsUsed: afterConsume?.creditsUsed ?? null,
  });
}

async function releaseCredits(userID: string, castID: string, amount: number, now: string): Promise<void> {
  const database = getTurso();
  const ledger = (await database.get(
    `SELECT credit_period_id AS creditPeriodID
     FROM cast_credit_ledger
     WHERE cast_id = ? AND user_id = ? AND entry_type = 'reserve'
     LIMIT 1`,
    castID,
    userID,
  )) as { creditPeriodID?: string } | null;
  if (!ledger?.creditPeriodID) return;

  await database.batch(
    [
      {
        sql: `UPDATE user_credit_periods
              SET credits_reserved = MAX(0, credits_reserved - ?), updated_at = ?
              WHERE id = ?
                AND NOT EXISTS (
                  SELECT 1 FROM cast_credit_ledger
                  WHERE cast_id = ? AND user_id = ? AND entry_type IN ('consume', 'release')
                )`,
        args: [amount, now, ledger.creditPeriodID, castID, userID],
      },
      {
        sql: `INSERT OR IGNORE INTO cast_credit_ledger
              (id, user_id, cast_id, credit_period_id, amount, entry_type, idempotency_key, note, created_at)
              VALUES (?, ?, ?, ?, ?, 'release', ?, 'Cast generation failed', ?)`,
        args: [randomUUID(), userID, castID, ledger.creditPeriodID, -amount, `release:${castID}`, now],
      },
    ],
    "immediate",
  );
}

async function currentPlanTier(userID: string): Promise<string> {
  const subscription = await effectiveSubscriptionForUser(getTurso(), userID);
  const resolvedTier = subscription.effectivePlanTier;
  logCastEvent("plan resolved", {
    userID,
    planTier: resolvedTier,
    billingPlanTier: subscription.billingPlanTier,
    effectiveIsActive: subscription.effectiveIsActive,
    source: subscription.source,
    updatedAt: subscription.updatedAt,
    overrideExpiresAt: subscription.overrideExpiresAt,
  });
  return resolvedTier;
}

function monthStart(value: string): string {
  const date = new Date(value);
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1)).toISOString();
}

function nextMonthStart(value: string): string {
  const date = new Date(value);
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1)).toISOString();
}

export async function createCast(userID: string, input: CreateCastInput): Promise<CastRecord> {
  const pipelineStartedAt = Date.now();
  logCastEvent("pipeline started", {
    userID,
    sourceCount: Array.isArray(input.sources) ? input.sources.length : null,
    durationMinutes: input.durationMinutes ?? 10,
    environment: process.env.NODE_ENV ?? "unknown",
    apiBaseConfigured: Boolean(process.env.TURSO_DATABASE_URL),
  });
  validateInput(input);

  const database = getTurso();
  const castID = randomUUID();
  const jobID = randomUUID();
  const now = new Date().toISOString();
  const durationMinutes = input.durationMinutes ?? 10;
  // 2分の開発テストCastも、最小1クレジットとして扱います。
  const creditCost = Math.max(1, Math.ceil(durationMinutes / 5));
  const title = normalizeTitle(input.title, input.sources);
  const idempotencyKey = `cast:${userID}:${castID}`;
  const languageRow = (await database.get(
    "SELECT preferred_language AS preferredLanguage FROM users WHERE id = ? LIMIT 1",
    userID,
  )) as { preferredLanguage?: CastLanguage } | null;
  const language: CastLanguage = languageRow?.preferredLanguage === "english" ? "english" : "japanese";
  logCastEvent("cast metadata resolved", {
    userID,
    castID,
    durationMinutes,
    creditCost,
    language,
    sourceCount: input.sources.length,
  });

  const resolvedSources = await Promise.allSettled(
    input.sources.map(async (source) => ({
      ...source,
      text: await resolveSourceText(source),
    })),
  );
  const sourceContents = resolvedSources.flatMap((result, index) => {
    if (result.status === "fulfilled") return [result.value];

    const source = input.sources[index];
    logCastEvent("source skipped after fetch failure", {
      userID,
      castID,
      url: source.url,
      title: source.title ?? null,
      reason: safeErrorMessage(result.reason),
    });
    return [];
  });
  const minimumUsableSources = input.internalKind === "daily_news"
    ? 5
    : (process.env.NODE_ENV !== "production" ? 1 : 2);
  if (sourceContents.length < minimumUsableSources) {
    throw new Error(`SOURCE_FETCH_INSUFFICIENT_SOURCES_${sourceContents.length}`);
  }
  logCastEvent("source contents resolved", {
    userID,
    castID,
    sourceCount: sourceContents.length,
    characterCounts: sourceContents.map((source) => source.text.length),
    elapsedMs: Date.now() - pipelineStartedAt,
  });

  await moderateSourceContents(sourceContents, language);

  try {
    await database.batch(
      [
      {
        sql: `INSERT INTO casts
          (id, user_id, title, duration_minutes, language, status, progress_percent, credit_cost, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, 'processing', 0, ?, ?, ?)`,
        args: [castID, userID, title, durationMinutes, language, creditCost, now, now],
      },
      ...sourceContents.map((source, index) => ({
        sql: `INSERT INTO cast_sources
          (id, cast_id, source_order, source_url, source_title, source_text, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)`,
        args: [
          randomUUID(),
          castID,
          index,
          source.url,
          source.title ?? null,
          source.text,
          now,
        ],
      })),
      {
        sql: `INSERT INTO cast_generation_jobs
          (id, cast_id, idempotency_key, status, attempt_count, queued_at, started_at)
          VALUES (?, ?, ?, 'processing', 1, ?, ?)`,
        args: [jobID, castID, idempotencyKey, now, now],
      },
      ],
      "immediate",
    );
    logCastEvent("cast records created", { userID, castID, jobID });
    // cast_credit_ledger.cast_id が casts.id を参照するため、Cast本体を先に作成します。
    await reserveCredits(userID, castID, creditCost, now);
    logCastEvent("cast credits reserved after record creation", { userID, castID, amount: creditCost });
  } catch (error) {
    const failedAt = new Date().toISOString();
    console.error("[cast] cast record creation failed", {
      userID,
      castID,
      jobID,
      message: error instanceof Error ? error.message : String(error),
    });
    await releaseCredits(userID, castID, creditCost, failedAt);
    await database.batch(
      [
        {
          sql: `UPDATE casts
                SET status = 'failed', error_message = ?, updated_at = ?
                WHERE id = ? AND user_id = ?`,
          args: [safeErrorMessage(error), failedAt, castID, userID],
        },
        {
          sql: `UPDATE cast_generation_jobs
                SET status = 'failed', finished_at = ?, last_error = ?
                WHERE id = ? AND cast_id = ?`,
          args: [failedAt, safeErrorMessage(error), jobID, castID],
        },
      ],
      "immediate",
    );
    throw error;
  }

  await updateCastProgress(castID, 10);
  return processCastGeneration(userID, castID, jobID, language, title, durationMinutes, creditCost, sourceContents);
}

/** Enqueues a user Cast without holding the HTTP request open for AI/audio generation. */
export async function enqueueCast(userID: string, input: CreateCastInput): Promise<CastRecord> {
  validateInput(input);
  const database = getTurso();
  const castID = randomUUID();
  const jobID = randomUUID();
  const now = new Date().toISOString();
  const durationMinutes = input.durationMinutes ?? 10;
  const creditCost = Math.max(1, Math.ceil(durationMinutes / 5));
  const title = normalizeTitle(input.title, input.sources);
  const planTier = await currentPlanTier(userID);
  const priority = planTier === "pro" ? 10 : 0;
  const languageRow = (await database.get(
    "SELECT preferred_language AS preferredLanguage FROM users WHERE id = ? LIMIT 1",
    userID,
  )) as { preferredLanguage?: CastLanguage } | null;
  const language: CastLanguage = languageRow?.preferredLanguage === "english" ? "english" : "japanese";

  await database.batch([
    {
      sql: `INSERT INTO casts
        (id, user_id, title, duration_minutes, language, status, credit_cost, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, 'queued', ?, ?, ?)`,
      args: [castID, userID, title, durationMinutes, language, creditCost, now, now],
    },
    ...input.sources.map((source, index) => ({
      sql: `INSERT INTO cast_sources
        (id, cast_id, source_order, source_url, source_title, source_text, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)`,
      args: [randomUUID(), castID, index, source.url, source.title ?? null, source.text ?? null, now],
    })),
    {
      sql: `INSERT INTO cast_generation_jobs
        (id, cast_id, idempotency_key, status, priority, attempt_count, queued_at)
        VALUES (?, ?, ?, 'queued', ?, 0, ?)`,
      args: [jobID, castID, `cast:${userID}:${castID}`, priority, now],
    },
  ], "immediate");

  try {
    await reserveCredits(userID, castID, creditCost, now);
  } catch (error) {
    const message = safeErrorMessage(error);
    await database.batch([
      { sql: "UPDATE casts SET status = 'failed', error_message = ?, updated_at = ? WHERE id = ?", args: [message, new Date().toISOString(), castID] },
      { sql: "UPDATE cast_generation_jobs SET status = 'failed', finished_at = ?, last_error = ? WHERE id = ?", args: [new Date().toISOString(), message, jobID] },
    ], "immediate");
    throw error;
  }

  logCastEvent("cast queued", { userID, castID, jobID, durationMinutes, creditCost, planTier, priority });
  return getCast(userID, castID);
}

export async function processNextCastGenerationJob(): Promise<{ processed: boolean; castID?: string; jobID?: string; error?: string }> {
  const database = getTurso();
  const now = new Date();
  const nowISO = now.toISOString();
  const staleBefore = new Date(now.getTime() - 6 * 60 * 1000).toISOString();
  const row = (await database.get(
    `SELECT j.id AS jobID, j.cast_id AS castID, c.user_id AS userID,
            c.title, c.duration_minutes AS durationMinutes, c.credit_cost AS creditCost,
            c.language, j.status AS jobStatus, j.priority, j.attempt_count AS attemptCount
     FROM cast_generation_jobs j JOIN casts c ON c.id = j.cast_id
     WHERE j.status = 'queued'
        OR (j.status = 'processing' AND j.started_at IS NOT NULL AND j.started_at <= ?)
     ORDER BY j.priority DESC, j.queued_at LIMIT 1`,
    staleBefore,
  )) as {
    jobID?: string;
    castID?: string;
    userID?: string;
    title?: string;
    durationMinutes?: number;
    creditCost?: number;
    language?: CastLanguage;
    jobStatus?: string;
    priority?: number;
    attemptCount?: number;
  } | null;
  if (!row?.jobID || !row.castID || !row.userID || !row.title || !row.durationMinutes || !row.creditCost) return { processed: false };

  if (row.jobStatus === "processing" && (row.attemptCount ?? 0) >= 3) {
    const message = "CAST_WORKER_ATTEMPTS_EXHAUSTED";
    await database.batch([
      { sql: "UPDATE casts SET status = 'failed', error_message = ?, updated_at = ? WHERE id = ?", args: [message, nowISO, row.castID] },
      { sql: "UPDATE cast_generation_jobs SET status = 'failed', finished_at = ?, last_error = ? WHERE id = ?", args: [nowISO, message, row.jobID] },
    ], "immediate");
    await releaseCredits(row.userID, row.castID, row.creditCost, nowISO);
    logCastEvent("stale queued cast exhausted", { userID: row.userID, castID: row.castID, jobID: row.jobID });
    return { processed: true, castID: row.castID, jobID: row.jobID, error: message };
  }

  const claimed = await database.run(
    `UPDATE cast_generation_jobs
     SET status = 'processing', attempt_count = attempt_count + 1, started_at = ?, finished_at = NULL
     WHERE id = ?
       AND (status = 'queued' OR (status = 'processing' AND started_at IS NOT NULL AND started_at <= ?))`,
    nowISO,
    row.jobID,
    staleBefore,
  );
  if (claimed.changes !== 1) return { processed: false };

  await database.run("UPDATE casts SET status = 'processing', updated_at = ? WHERE id = ?", nowISO, row.castID);
  try {
    const rawSources = (await database.all(
      `SELECT source_url AS url, source_title AS title, source_text AS text
       FROM cast_sources WHERE cast_id = ? ORDER BY source_order`, row.castID,
    )) as CastSourceInput[];
    const resolvedSources = await Promise.allSettled(rawSources.map(async source => ({
      ...source,
      text: source.text ?? await resolveSourceText(source),
    })));
    const sources = resolvedSources.flatMap((result, index) => {
      if (result.status === "fulfilled") return [result.value];
      const source = rawSources[index];
      logCastEvent("source skipped after fetch failure", {
        userID: row.userID,
        castID: row.castID,
        url: source.url,
        title: source.title ?? null,
        reason: safeErrorMessage(result.reason),
      });
      return [];
    });
    const minimumUsableSources = 2;
    if (sources.length < minimumUsableSources) {
      throw new Error(`SOURCE_FETCH_INSUFFICIENT_SOURCES_${sources.length}`);
    }
    await moderateSourceContents(sources, row.language ?? "japanese");
    await processCastGeneration(row.userID, row.castID, row.jobID, row.language ?? "japanese", row.title, row.durationMinutes, row.creditCost, sources);
    return { processed: true, castID: row.castID, jobID: row.jobID };
  } catch (error) {
    const message = safeErrorMessage(error);
    const failedAt = new Date().toISOString();
    await database.batch([
      { sql: "UPDATE casts SET status = 'failed', error_message = ?, updated_at = ? WHERE id = ?", args: [message, failedAt, row.castID] },
      { sql: "UPDATE cast_generation_jobs SET status = 'failed', finished_at = ?, last_error = ? WHERE id = ?", args: [failedAt, message, row.jobID] },
    ], "immediate");
    await releaseCredits(row.userID, row.castID, row.creditCost, failedAt);
    logCastEvent("queued cast failed", { userID: row.userID, castID: row.castID, jobID: row.jobID, code: message });
    return { processed: true, castID: row.castID, jobID: row.jobID, error: message };
  }
}

async function processCastGeneration(
  userID: string,
  castID: string,
  jobID: string,
  language: CastLanguage,
  title: string,
  durationMinutes: number,
  creditCost: number,
  sourceContents: Array<CastSourceInput & { text: string }>,
): Promise<CastRecord> {
  const database = getTurso();
  try {
    // Start with a small, visible step after the worker claims the job so the
    // client does not jump directly from queued 0% to the middle of the flow.
    await updateCastProgress(castID, 5);
    const generated = await withProgressTicker(
      castID,
      5,
      55,
      () => createCastContent(userID, language, title, durationMinutes, sourceContents),
    );
    const script = generated.script;
    await updateCastProgress(castID, 55);
    const audio = await withProgressTicker(castID, 55, 85, () => createAudio(script));
    await updateCastProgress(castID, 85);
    const objectKey = `casts/${userID}/${castID}/audio.mp3`;
    await getR2Client().send(new PutObjectCommand({
      Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"), Key: objectKey, Body: audio,
      ContentType: "audio/mpeg", CacheControl: "private, max-age=3600",
    }));
    const artworkObjectKey = await storeCastArtwork(userID, castID);
    await updateCastProgress(castID, 95);
    const completedAt = new Date().toISOString();
    await database.batch([
      { sql: `UPDATE casts SET title = ?, summary = ?, transcript = ?, status = 'completed', progress_percent = 100, audio_object_key = ?, artwork_object_key = ?, updated_at = ?, completed_at = ?, error_message = NULL WHERE id = ? AND user_id = ?`, args: [generated.title, buildSummary(script), script, objectKey, artworkObjectKey, completedAt, completedAt, castID, userID] },
      { sql: `UPDATE cast_generation_jobs SET status = 'completed', finished_at = ?, last_error = NULL WHERE id = ? AND cast_id = ?`, args: [completedAt, jobID, castID] },
    ], "immediate");
    await consumeCredits(userID, castID, creditCost, completedAt);
    try {
      await sendUserPush(userID, {
        title: "Castが作成されました",
        body: "あなたのCastを聴いてみましょう",
        deepLink: `stackcast://cast/${castID}`,
      });
    } catch (pushError) {
      console.warn("[cast] completion push failed; Cast remains completed", {
        userID,
        castID,
        message: pushError instanceof Error ? pushError.message : String(pushError),
      });
    }
    logCastEvent("pipeline completed", { userID, castID, jobID });
    return getCast(userID, castID);
  } catch (error) {
    const message = safeErrorMessage(error);
    const failedAt = new Date().toISOString();
    await database.batch([
      { sql: "UPDATE casts SET status = 'failed', error_message = ?, updated_at = ? WHERE id = ? AND user_id = ?", args: [message, failedAt, castID, userID] },
      { sql: "UPDATE cast_generation_jobs SET status = 'failed', finished_at = ?, last_error = ? WHERE id = ? AND cast_id = ?", args: [failedAt, message, jobID, castID] },
    ], "immediate");
    await releaseCredits(userID, castID, creditCost, failedAt);
    throw error;
  }
}

async function updateCastProgress(castID: string, progressPercent: number): Promise<void> {
  await getTurso().run(
    "UPDATE casts SET progress_percent = ?, updated_at = ? WHERE id = ? AND status = 'processing'",
    Math.max(0, Math.min(100, Math.round(progressPercent))),
    new Date().toISOString(),
    castID,
  );
}

async function withProgressTicker<T>(
  castID: string,
  startPercent: number,
  endPercent: number,
  operation: () => Promise<T>,
): Promise<T> {
  let progress = startPercent;
  const timer = setInterval(() => {
    if (progress >= endPercent - 1) return;
    progress += 1;
    void updateCastProgress(castID, progress).catch((error) => {
      console.warn("[cast] progress update skipped", {
        castID,
        progressPercent: progress,
        message: error instanceof Error ? error.message : String(error),
      });
    });
  }, 1_000);

  try {
    return await operation();
  } finally {
    clearInterval(timer);
  }
}

/**
 * Stores the current fallback artwork per Cast. Replace the bytes returned by
 * this helper with an AI-generated image when the image provider is selected.
 */
async function storeCastArtwork(userID: string, castID: string): Promise<string> {
  const artwork = await readFile(join(process.cwd(), "public", "cast-artwork.png"));
  const objectKey = `casts/${userID}/${castID}/artwork.png`;
  await getR2Client().send(new PutObjectCommand({
    Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"),
    Key: objectKey,
    Body: artwork,
    ContentType: "image/png",
    CacheControl: "private, max-age=86400",
  }));
  return objectKey;
}

async function moderateSourceContents(
  sources: Array<CastSourceInput & { text: string }>,
  language: CastLanguage,
): Promise<void> {
  const apiKey = requiredEnvironmentVariable("OPENAI_API_KEY");
  const input = sources
    .map((source) => `${source.title ?? ""}\n${source.text}`)
    .join("\n\n")
    .slice(0, 100_000);
  const response = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    signal: AbortSignal.timeout(30_000),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: "omni-moderation-latest", input }),
  });

  if (!response.ok) throw new Error(`CONTENT_MODERATION_FAILED_${response.status}`);
  const payload = (await response.json()) as {
    results?: Array<{ flagged?: boolean; categories?: Record<string, boolean> }>;
  };
  const matchedCategories = new Set(
    payload.results?.flatMap((result) =>
      castSafetyPolicy.blockedCategories.filter((category) => result.categories?.[category] === true),
    ) ?? [],
  );
  if (matchedCategories.size > 0 || payload.results?.some((result) => result.flagged)) {
    console.warn("[cast] source content rejected by safety policy", {
      language,
      categories: [...matchedCategories],
    });
    throw new Error(`CAST_CONTENT_NOT_ALLOWED_${[...matchedCategories].join("_") || "SAFETY"}`);
  }
}

export async function listCasts(userID: string): Promise<CastRecord[]> {
  const database = getTurso();
  const rows = (await database.all(
    `SELECT casts.id, casts.title, casts.summary, casts.transcript, casts.duration_minutes AS durationMinutes,
            casts.status, casts.progress_percent AS progressPercent, casts.audio_object_key AS audioObjectKey,
            casts.artwork_object_key AS artworkObjectKey, casts.credit_cost AS creditCost,
            casts.error_message AS errorMessage, casts.created_at AS createdAt,
            casts.updated_at AS updatedAt, casts.completed_at AS completedAt,
            cast_shares.token AS shareToken
     FROM casts
     LEFT JOIN cast_shares ON cast_shares.cast_id = casts.id
     WHERE casts.user_id = ?
     ORDER BY casts.created_at DESC
     LIMIT 100`,
    userID,
  )) as CastRow[];

  return Promise.all(rows.map((row) => addSignedURL(row)));
}

export async function getCast(userID: string, castID: string): Promise<CastRecord> {
  const database = getTurso();
  const row = (await database.get(
    `SELECT casts.id, casts.title, casts.summary, casts.transcript, casts.duration_minutes AS durationMinutes,
            casts.status, casts.progress_percent AS progressPercent, casts.audio_object_key AS audioObjectKey,
            casts.artwork_object_key AS artworkObjectKey, casts.credit_cost AS creditCost,
            casts.error_message AS errorMessage, casts.created_at AS createdAt,
            casts.updated_at AS updatedAt, casts.completed_at AS completedAt,
            cast_shares.token AS shareToken
     FROM casts
     LEFT JOIN cast_shares ON cast_shares.cast_id = casts.id
     WHERE casts.id = ? AND casts.user_id = ?
     LIMIT 1`,
    castID,
    userID,
  )) as CastRow | null;

  if (!row) {
    throw new Error("CAST_NOT_FOUND");
  }

  return addSignedURL(row);
}

async function addSignedURL(row: CastRow): Promise<CastRecord> {
  const audioURL = row.audioObjectKey
    ? await signedCastAudioURL(row.audioObjectKey)
    : null;
  const artworkURL = row.artworkObjectKey
    ? await signedCastArtworkURL(row.artworkObjectKey)
    : defaultCastArtworkURL();

  return { ...row, audioURL, artworkURL };
}

function defaultCastArtworkURL(): string | null {
  const backendURL = process.env.BACKEND_URL?.trim();
  if (!backendURL) return null;
  return new URL("/cast-artwork.png", backendURL).toString();
}

export async function signedCastAudioURL(objectKey: string): Promise<string> {
  return getSignedUrl(
    getR2Client(),
    new GetObjectCommand({
      Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"),
      Key: objectKey,
    }),
    { expiresIn: signedURLLifetimeSeconds },
  );
}

async function signedCastArtworkURL(objectKey: string): Promise<string> {
  return getSignedUrl(
    getR2Client(),
    new GetObjectCommand({
      Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"),
      Key: objectKey,
    }),
    { expiresIn: signedURLLifetimeSeconds },
  );
}

async function createCastContent(
  userID: string,
  language: CastLanguage,
  title: string,
  durationMinutes: number,
  sources: Array<CastSourceInput & { text: string }>,
): Promise<GeneratedCastContent> {
  const apiKey = requiredEnvironmentVariable("OPENAI_API_KEY");
  const targetCharacters = durationMinutes * 300;
  const maxOutputTokens = durationMinutes * 700;
  const safetyIdentifier = createHash("sha256").update(userID).digest("hex");
  const articleText = sources
    .map(
      (source, index) =>
        `【記事${index + 1}】\nタイトル: ${source.title ?? "不明"}\nURL: ${source.url}\n本文:\n${source.text}`,
    )
    .join("\n\n");

  logCastEvent("openai payload prepared", {
    userID,
    model: openAIModel,
    language,
    sourceCount: sources.length,
    inputCharacters: articleText.length,
    targetCharacters,
    maxOutputTokens,
  });

  const requestStartedAt = Date.now();
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    signal: AbortSignal.timeout(120_000),
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: openAIModel,
      reasoning: { effort: "low", context: "current_turn" },
      instructions: buildCastGenerationPrompt(language, durationMinutes, targetCharacters),
      input: `参考タイトル: ${title}\n\n${articleText}`,
      text: {
        format: {
          type: "json_schema",
          name: "cast_content",
          strict: true,
          schema: {
            type: "object",
            properties: {
              title: { type: "string" },
              script: { type: "string" },
            },
            required: ["title", "script"],
            additionalProperties: false,
          },
        },
      },
      max_output_tokens: maxOutputTokens,
      safety_identifier: safetyIdentifier,
      store: false,
    }),
  });

  if (!response.ok) {
    const errorCode = await readOpenAIErrorCode(response);
    console.error("[cast] openai request returned error", {
      userID,
      status: response.status,
      errorCode,
      elapsedMs: Date.now() - requestStartedAt,
    });
    throw new Error(
      `OPENAI_REQUEST_FAILED_${response.status}${errorCode ? `_${errorCode}` : ""}`,
    );
  }

  const payload = (await response.json()) as {
    status?: "completed" | "failed" | "incomplete" | "cancelled" | "queued" | "in_progress";
    incomplete_details?: { reason?: string } | null;
    output?: Array<{
      type?: string;
      content?: Array<
        | { type: "output_text"; text?: string }
        | { type: "refusal"; refusal?: string }
        | { type?: string }
      >;
    }>;
  };
  if (payload.status === "incomplete") {
    throw new Error(`OPENAI_INCOMPLETE_${payload.incomplete_details?.reason ?? "UNKNOWN"}`);
  }
  if (payload.status && payload.status !== "completed") {
    throw new Error(`OPENAI_RESPONSE_${payload.status.toUpperCase()}`);
  }

  const contentItems = payload.output
    ?.filter((item) => item.type === "message")
    .flatMap((item) => item.content ?? []) ?? [];
  if (contentItems.some((content) => content.type === "refusal")) {
    throw new Error("OPENAI_REFUSED");
  }

  const outputText = contentItems
    .filter(
      (content): content is { type: "output_text"; text?: string } =>
        content.type === "output_text",
    )
    .map((content) => content.text ?? "")
    .join("\n")
    .trim();

  if (!outputText) {
    throw new Error("OPENAI_EMPTY_OUTPUT");
  }

  let generated: GeneratedCastContent;
  try {
    generated = JSON.parse(outputText) as GeneratedCastContent;
  } catch {
    throw new Error("OPENAI_INVALID_STRUCTURED_OUTPUT");
  }

  const script = typeof generated.script === "string" ? generated.script.trim() : "";
  if (!script) throw new Error("OPENAI_EMPTY_SCRIPT");

  return {
    title: sanitizeGeneratedTitle(generated.title, language, title),
    script,
  };
}

function sanitizeGeneratedTitle(
  value: unknown,
  language: CastLanguage,
  fallback: string,
): string {
  const normalized = typeof value === "string"
    ? value.replace(/\s+/g, " ").replace(/^[「『\"']+|[」』\"']+$/g, "").trim()
    : "";
  const source = normalized || fallback;
  const maximumCharacters = language === "english" ? 40 : 18;
  return Array.from(source).slice(0, maximumCharacters).join("").trim();
}

async function readOpenAIErrorCode(response: Response): Promise<string | null> {
  try {
    const payload = (await response.json()) as { error?: { code?: unknown; type?: unknown } };
    const value = payload.error?.code ?? payload.error?.type;
    return typeof value === "string"
      ? value.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 80)
      : null;
  } catch {
    return null;
  }
}

async function createAudio(script: string): Promise<Uint8Array> {
  const apiKey = requiredEnvironmentVariable("FISH_AUDIO_API_KEY");
  const referenceID = process.env.FISH_AUDIO_REFERENCE_ID?.trim();
  const requestStartedAt = Date.now();
  const response = await fetch(fishAudioEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      model: fishAudioModel,
    },
    body: JSON.stringify({
      text: buildFishAudioInput(script),
      ...(referenceID ? { reference_id: referenceID } : {}),
      format: "mp3",
      mp3_bitrate: 128,
      sample_rate: 44_100,
      normalize: true,
      latency: "normal",
      chunk_length: 200,
      condition_on_previous_chunks: true,
      prosody: { speed: 1, volume: 0, normalize_loudness: true },
    }),
  });

  if (!response.ok) {
    console.error("[cast] fish audio request returned error", {
      status: response.status,
      model: fishAudioModel,
      elapsedMs: Date.now() - requestStartedAt,
    });
    throw new Error(`FISH_AUDIO_REQUEST_FAILED_${response.status}`);
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (contentType.includes("application/json")) {
    throw new Error("FISH_AUDIO_INVALID_AUDIO_RESPONSE");
  }

  const audio = new Uint8Array(await response.arrayBuffer());
  if (audio.byteLength === 0) {
    throw new Error("FISH_AUDIO_EMPTY_OUTPUT");
  }

  logCastEvent("fish audio bytes received", { bytes: audio.byteLength, elapsedMs: Date.now() - requestStartedAt });
  return audio;
}

async function resolveSourceText(source: CastSourceInput): Promise<string> {
  if (source.text?.trim()) {
    logCastEvent("source text supplied by client", { url: source.url, characters: source.text.length });
    return limitText(source.text);
  }

  const url = new URL(source.url);
  const requestStartedAt = Date.now();
  logCastEvent("source fetch started", { url: source.url });
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error("SOURCE_URL_PROTOCOL_UNSUPPORTED");
  }

  const response = await fetch(url, {
    headers: { "User-Agent": "Tsundoku/1.0 article reader" },
    signal: AbortSignal.timeout(15_000),
  });
  logCastEvent("source fetched", { url: source.url, status: response.status, elapsedMs: Date.now() - requestStartedAt });
  if (!response.ok) {
    throw new Error(`SOURCE_FETCH_FAILED_${response.status}`);
  }

  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("text/html") && !contentType.includes("text/plain")) {
    throw new Error("SOURCE_CONTENT_TYPE_UNSUPPORTED");
  }

  return limitText(stripHTML(await response.text()));
}

function validateInput(input: CreateCastInput): void {
  const isDevelopmentTest = process.env.NODE_ENV !== "production";
  const isDailyNews = input.internalKind === "daily_news";
  const minimumSources = isDailyNews ? 5 : (isDevelopmentTest ? 1 : 3);
  const maximumSources = isDailyNews ? 5 : 4;
  if (!Array.isArray(input.sources) || input.sources.length < minimumSources || input.sources.length > maximumSources) {
    throw new Error("CAST_REQUIRES_THREE_TO_FOUR_SOURCES");
  }
  for (const source of input.sources) {
    if (!source.url?.trim()) throw new Error("SOURCE_URL_REQUIRED");
    if (source.text && source.text.length > maxSourceCharacters) {
      throw new Error("SOURCE_TEXT_TOO_LONG");
    }
  }
  if (input.durationMinutes && !isSupportedDuration(input.durationMinutes, isDevelopmentTest)) {
    throw new Error("CAST_DURATION_UNSUPPORTED");
  }
}

function isSupportedDuration(value: number, isDevelopmentTest: boolean): boolean {
  return Number.isInteger(value) && ((value >= 5 && value <= 20) || (isDevelopmentTest && value === 2));
}

function normalizeTitle(title: string | undefined, sources: CastSourceInput[]): string {
  const normalized = title?.trim();
  if (normalized) return normalized.slice(0, 200);
  return `${sources[0]?.title?.trim() || "Tsundoku Cast"} のまとめ`.slice(0, 200);
}

function buildSummary(script: string): string {
  return script.replace(/\s+/g, " ").trim().slice(0, 1_000);
}

function stripHTML(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, " ")
    .trim();
}

function limitText(text: string): string {
  const normalized = text.replace(/\s+/g, " ").trim();
  if (!normalized) throw new Error("SOURCE_TEXT_EMPTY");
  return normalized.slice(0, maxSourceCharacters);
}

function getR2Client(): S3Client {
  if (r2Client) return r2Client;

  r2Client = new S3Client({
    region: "auto",
    endpoint: requiredEnvironmentVariable("R2_ENDPOINT"),
    credentials: {
      accessKeyId: requiredEnvironmentVariable("R2_ACCESS_KEY_ID"),
      secretAccessKey: requiredEnvironmentVariable("R2_SECRET_ACCESS_KEY"),
    },
  });
  return r2Client;
}

function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`MISSING_ENV_${name}`);
  return value;
}

function safeErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message.slice(0, 500);
  return "CAST_GENERATION_FAILED";
}

import { GetObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { createHash, randomUUID } from "node:crypto";
import { getTurso } from "@/lib/turso";
import { effectiveSubscriptionForUser } from "@/lib/billing/effective-plan";
import { buildCastGenerationPrompt, buildFishAudioInput, castSafetyPolicy, type CastLanguage } from "./prompt";

const openAIModel = "gpt-5.6-luna";
const fishAudioEndpoint = "https://api.fish.audio/v1/tts";
const fishAudioModel = "s2.1-pro-free";
const fishAudioFreeModelEnd = Date.parse("2026-09-01T00:00:00Z");
const maxSourceCharacters = 30_000;
const signedURLLifetimeSeconds = 60 * 60;

export type CastSourceInput = {
  url: string;
  title?: string;
  text?: string;
};

export type CreateCastInput = {
  title?: string;
  durationMinutes?: 2 | 5 | 10 | 15 | 20;
  sources: CastSourceInput[];
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
  audioObjectKey: string | null;
  audioURL?: string | null;
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
  audioObjectKey: string | null;
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
  free: 3,
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
              WHERE id = ?`,
        args: [amount, now, ledger.creditPeriodID],
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

  const sourceContents = await Promise.all(
    input.sources.map(async (source) => ({
      ...source,
      text: await resolveSourceText(source),
    })),
  );
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
          (id, user_id, title, duration_minutes, language, status, credit_cost, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, 'processing', ?, ?, ?)`,
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

  try {
    const openAIStartedAt = Date.now();
    logCastEvent("openai request started", { userID, castID, model: openAIModel, language, durationMinutes });
    const generated = await createCastContent(userID, language, title, durationMinutes, sourceContents);
    const script = generated.script;
    logCastEvent("openai request completed", {
      userID,
      castID,
      titleCharacters: Array.from(generated.title).length,
      scriptCharacters: script.length,
      elapsedMs: Date.now() - openAIStartedAt,
    });
    const fishStartedAt = Date.now();
    logCastEvent("fish audio request started", { userID, castID, model: fishAudioModel, scriptCharacters: script.length });
    const audio = await createAudio(script);
    logCastEvent("fish audio request completed", {
      userID,
      castID,
      audioBytes: audio.byteLength,
      elapsedMs: Date.now() - fishStartedAt,
    });
    const objectKey = `casts/${userID}/${castID}/audio.mp3`;

    logCastEvent("r2 upload started", { userID, castID, objectKey, audioBytes: audio.byteLength });
    await getR2Client().send(
      new PutObjectCommand({
        Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"),
        Key: objectKey,
        Body: audio,
        ContentType: "audio/mpeg",
        CacheControl: "private, max-age=3600",
      }),
    );
    logCastEvent("r2 upload completed", { userID, castID, objectKey, audioBytes: audio.byteLength });

    const completedAt = new Date().toISOString();
    await database.batch(
      [
        {
          sql: `UPDATE casts
            SET title = ?, summary = ?, transcript = ?, status = 'completed', audio_object_key = ?,
                updated_at = ?, completed_at = ?, error_message = NULL
            WHERE id = ? AND user_id = ?`,
          args: [generated.title, buildSummary(script), script, objectKey, completedAt, completedAt, castID, userID],
        },
        {
          sql: `UPDATE cast_generation_jobs
            SET status = 'completed', finished_at = ?, last_error = NULL
            WHERE id = ? AND cast_id = ?`,
          args: [completedAt, jobID, castID],
        },
      ],
      "immediate",
    );
    await consumeCredits(userID, castID, creditCost, completedAt);

    logCastEvent("pipeline completed", {
      userID,
      castID,
      jobID,
      status: "completed",
      elapsedMs: Date.now() - pipelineStartedAt,
    });

    return await getCast(userID, castID);
  } catch (error) {
    const message = safeErrorMessage(error);
    console.error("[cast] pipeline failed", {
      userID,
      castID,
      jobID,
      code: message,
      stack: error instanceof Error ? error.stack : undefined,
    });
    const failedAt = new Date().toISOString();
    await database.batch(
      [
        {
          sql: `UPDATE casts
            SET status = 'failed', error_message = ?, updated_at = ?
            WHERE id = ? AND user_id = ?`,
          args: [message, failedAt, castID, userID],
        },
        {
          sql: `UPDATE cast_generation_jobs
            SET status = 'failed', finished_at = ?, last_error = ?
            WHERE id = ? AND cast_id = ?`,
          args: [failedAt, message, jobID, castID],
        },
      ],
      "immediate",
    );
    await releaseCredits(userID, castID, creditCost, failedAt);
    logCastEvent("pipeline marked failed", { userID, castID, jobID, code: message });
    throw error;
  }
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
            casts.status, casts.audio_object_key AS audioObjectKey, casts.credit_cost AS creditCost,
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
            casts.status, casts.audio_object_key AS audioObjectKey, casts.credit_cost AS creditCost,
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

  return { ...row, audioURL };
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
  if (Date.now() >= fishAudioFreeModelEnd) {
    console.error("[cast] fish audio free model expired", { model: fishAudioModel, freeModelEnd: fishAudioFreeModelEnd });
    throw new Error("FISH_AUDIO_FREE_MODEL_EXPIRED");
  }

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
  const minimumSources = isDevelopmentTest ? 1 : 3;
  if (!Array.isArray(input.sources) || input.sources.length < minimumSources || input.sources.length > 4) {
    throw new Error("CAST_REQUIRES_THREE_TO_FOUR_SOURCES");
  }
  for (const source of input.sources) {
    if (!source.url?.trim()) throw new Error("SOURCE_URL_REQUIRED");
    if (source.text && source.text.length > maxSourceCharacters) {
      throw new Error("SOURCE_TEXT_TOO_LONG");
    }
  }
  const allowedDurations = isDevelopmentTest ? [2, 5, 10, 15, 20] : [5, 10, 15, 20];
  if (input.durationMinutes && !allowedDurations.includes(input.durationMinutes)) {
    throw new Error("CAST_DURATION_UNSUPPORTED");
  }
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

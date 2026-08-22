import { randomUUID } from "node:crypto";
import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { getTurso } from "@/lib/turso";
import { tokyoEditionDate } from "@/lib/recommendations/daily-edition";

export const runtime = "nodejs";

const allowedAgeBands = new Set(["under_18", "18_24", "25_34", "35_44", "45_54", "55_plus", "unspecified"]);

export async function GET(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  return Response.json({ profile: await readProfile(userID) });
}

export async function PUT(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  const input = await readInput(request);
  if (!input) return errorResponse("invalid_input", "Profile settings are invalid.", 400);

  const now = new Date().toISOString();
  const database = getTurso();
  const customInterestStatements = input.customInterests.map((interest) => ({
    sql: `INSERT INTO user_custom_interests
      (id, user_id, label, normalized_label, matched_topic_id, created_at, updated_at)
     SELECT ?, ?, ?, ?, id, ?, ? FROM recommendation_topics WHERE id = ? AND is_active = 1`,
    args: [randomUUID(), userID, interest.label, normalizeInterest(interest.label), now, now, interest.topicID],
  }));
  await database.batch([
    {
      sql: `INSERT INTO user_recommendation_profiles
        (user_id, age_band, gender, time_zone, personalization_enabled, daily_auto_cast_enabled,
         daily_cast_duration_minutes, ai_processing_consent_at, onboarding_completed_at,
         memory_version, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET
         age_band = excluded.age_band, gender = excluded.gender,
         time_zone = excluded.time_zone,
         personalization_enabled = excluded.personalization_enabled,
         daily_auto_cast_enabled = excluded.daily_auto_cast_enabled,
         daily_cast_duration_minutes = excluded.daily_cast_duration_minutes,
         ai_processing_consent_at = COALESCE(excluded.ai_processing_consent_at, user_recommendation_profiles.ai_processing_consent_at),
         onboarding_completed_at = excluded.onboarding_completed_at, updated_at = excluded.updated_at`,
      args: [userID, input.ageBand, input.gender, input.timeZone, input.personalizationEnabled ? 1 : 0,
        input.dailyAutoCastEnabled ? 1 : 0, input.dailyCastDurationMinutes,
        input.aiProcessingConsent ? now : null, now, now, now],
    },
    { sql: "DELETE FROM user_topic_preferences WHERE user_id = ?", args: [userID] },
    { sql: "DELETE FROM user_custom_interests WHERE user_id = ?", args: [userID] },
    ...input.topicIDs.map((topicID) => ({
      sql: `INSERT INTO user_topic_preferences
        (user_id, topic_id, preference, weight, source, created_at, updated_at)
       SELECT ?, id, 'like', 1, 'manual', ?, ? FROM recommendation_topics WHERE id = ? AND is_active = 1`,
      args: [userID, now, now, topicID],
    })),
    ...customInterestStatements,
  ], "immediate");
  await database.run(
    `DELETE FROM daily_news_editions
     WHERE user_id = ? AND edition_date = ? AND cast_id IS NULL`,
    userID, tokyoEditionDate(),
  );
  return Response.json({ profile: await readProfile(userID) });
}

export async function PATCH(request: Request) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  let body: { timeZone?: unknown; ageBand?: unknown; gender?: unknown };
  try {
    body = await request.json() as { timeZone?: unknown };
  } catch {
    return errorResponse("invalid_input", "Time zone is invalid.", 400);
  }
  const timeZone = normalizeTimeZone(body.timeZone);
  const ageBand = body.ageBand === undefined ? undefined : normalizeAgeBand(body.ageBand);
  const gender = body.gender === undefined ? undefined : normalizeGender(body.gender);
  if (body.timeZone !== undefined && !timeZone) return errorResponse("invalid_input", "Time zone is invalid.", 400);
  if (body.ageBand !== undefined && !ageBand) return errorResponse("invalid_input", "Age range is invalid.", 400);
  if (body.gender !== undefined && gender === undefined) return errorResponse("invalid_input", "Gender is invalid.", 400);
  const now = new Date().toISOString();
  const database = getTurso();
  const updates: string[] = [];
  const updateArgs: unknown[] = [];
  if (timeZone) { updates.push("time_zone = ?"); updateArgs.push(timeZone); }
  if (ageBand) {
    updates.push("age_band = ?"); updateArgs.push(ageBand);
    updates.push("onboarding_completed_at = ?"); updateArgs.push(now);
  }
  if (body.gender !== undefined) { updates.push("gender = ?"); updateArgs.push(gender); }
  updateArgs.push(now, userID);
  await database.batch([
    {
      sql: `INSERT OR IGNORE INTO user_recommendation_profiles
        (user_id, time_zone, created_at, updated_at)
       VALUES (?, ?, ?, ?)`,
      args: [userID, timeZone ?? "Asia/Tokyo", now, now],
    },
    {
      sql: `UPDATE user_recommendation_profiles SET ${updates.length > 0 ? `${updates.join(", ")}, ` : ""}updated_at = ? WHERE user_id = ?`,
      args: updateArgs,
    },
  ], "immediate");
  return Response.json({ timeZone: timeZone ?? null, ageBand: ageBand ?? null, gender: gender ?? null });
}

function normalizeAgeBand(value: unknown): string | null {
  return typeof value === "string" && allowedAgeBands.has(value) ? value : null;
}

function normalizeGender(value: unknown): string | null | undefined {
  if (value === null || value === "unspecified") return null;
  if (value === "female" || value === "male" || value === "non_binary") return value;
  return undefined;
}

type ProfileInput = {
  ageBand: string;
  gender: string | null;
  timeZone: string;
  personalizationEnabled: boolean;
  dailyAutoCastEnabled: boolean;
  dailyCastDurationMinutes: number;
  aiProcessingConsent: boolean;
  topicIDs: string[];
  customInterests: Array<{ label: string; topicID: string }>;
};

async function readInput(request: Request): Promise<ProfileInput | null> {
  try {
    const body = await request.json() as Partial<ProfileInput>;
    const topicIDs = [...new Set((body.topicIDs ?? []).filter((value): value is string => typeof value === "string"))];
    const customInterests = sanitizeCustomInterests(body.customInterests);
    const ageBand = typeof body.ageBand === "string" ? body.ageBand : "unspecified";
    const timeZone = normalizeTimeZone(body.timeZone) ?? "Asia/Tokyo";
    const duration = body.dailyCastDurationMinutes ?? 5;
    if (!allowedAgeBands.has(ageBand) || topicIDs.length + customInterests.length < 3 || ![5, 10, 15, 20].includes(duration)) return null;
    return {
      ageBand,
      gender: typeof body.gender === "string" ? body.gender.slice(0, 40) : null,
      timeZone,
      personalizationEnabled: body.personalizationEnabled !== false,
      dailyAutoCastEnabled: body.dailyAutoCastEnabled === true,
      dailyCastDurationMinutes: duration,
      aiProcessingConsent: body.aiProcessingConsent === true,
      topicIDs,
      customInterests,
    };
  } catch {
    return null;
  }
}

async function readProfile(userID: string) {
  const profile = await getTurso().get(
    `SELECT age_band AS ageBand, gender, time_zone AS timeZone,
            personalization_enabled AS personalizationEnabled,
            daily_auto_cast_enabled AS dailyAutoCastEnabled,
            daily_cast_duration_minutes AS dailyCastDurationMinutes,
            ai_processing_consent_at AS aiProcessingConsentAt,
            onboarding_completed_at AS onboardingCompletedAt
     FROM user_recommendation_profiles WHERE user_id = ?`,
    userID,
  );
  const topics = await getTurso().all(
    `SELECT p.topic_id AS id, t.name_ja AS nameJA, t.name_en AS nameEN, p.preference, p.weight
     FROM user_topic_preferences p JOIN recommendation_topics t ON t.id = p.topic_id
     WHERE p.user_id = ? ORDER BY t.sort_order`,
    userID,
  );
  const customInterests = await getTurso().all(
    `SELECT id, label, matched_topic_id AS topicID
     FROM user_custom_interests WHERE user_id = ? ORDER BY created_at`,
    userID,
  );
  return { ...(profile ?? { ageBand: "unspecified", timeZone: "Asia/Tokyo", personalizationEnabled: 1, dailyAutoCastEnabled: 0, dailyCastDurationMinutes: 5 }), topics, customInterests };
}

function normalizeTimeZone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const candidate = value.trim();
  if (!candidate || candidate.length > 80) return null;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: candidate }).format();
    return candidate;
  } catch {
    return null;
  }
}

function sanitizeCustomInterests(value: unknown): Array<{ label: string; topicID: string }> {
  if (!Array.isArray(value)) return [];
  const unique = new Map<string, { label: string; topicID: string }>();
  for (const item of value.slice(0, 10)) {
    if (!item || typeof item !== "object") continue;
    const candidate = item as { label?: unknown; topicID?: unknown };
    if (typeof candidate.label !== "string" || typeof candidate.topicID !== "string") continue;
    const label = candidate.label.trim().replace(/\s+/g, " ").slice(0, 40);
    const topicID = candidate.topicID.trim().slice(0, 40);
    if (label.length < 2 || topicID.length === 0) continue;
    unique.set(normalizeInterest(label), { label, topicID });
  }
  return [...unique.values()];
}

function normalizeInterest(value: string): string {
  return value.normalize("NFKC").trim().toLocaleLowerCase("ja-JP");
}

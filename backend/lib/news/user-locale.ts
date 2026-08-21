import { getTurso } from "../turso";

export type UserNewsLocale = {
  language: "japanese" | "english";
  timeZone: string;
  sourceCountry: string;
  topicIDs: string[];
};

export async function newsLocaleForUser(userID: string): Promise<UserNewsLocale> {
  const database = getTurso();
  const row = (await database.get(
    `SELECT u.preferred_language AS language, COALESCE(p.time_zone, 'Asia/Tokyo') AS timeZone,
            GROUP_CONCAT(CASE WHEN pref.preference = 'like' THEN pref.topic_id END) AS topicIDs
     FROM users u
     LEFT JOIN user_recommendation_profiles p ON p.user_id = u.id
     LEFT JOIN user_topic_preferences pref ON pref.user_id = u.id
     WHERE u.id = ?
     GROUP BY u.id, u.preferred_language, p.time_zone`,
    userID,
  )) as { language?: string | null; timeZone?: string | null; topicIDs?: string | null } | null;
  const timeZone = validTimeZone(row?.timeZone);
  return {
    language: row?.language === "english" ? "english" : "japanese",
    timeZone,
    sourceCountry: countryForTimeZone(timeZone),
    topicIDs: row?.topicIDs?.split(",").filter(Boolean) ?? [],
  };
}

export function countryForTimeZone(timeZone: string): string {
  if (timeZone === "Asia/Tokyo") return "japan";
  if (timeZone.startsWith("America/")) return "unitedstates";
  if (timeZone === "Europe/London") return "unitedkingdom";
  if (timeZone.startsWith("Europe/")) return "germany";
  if (timeZone.startsWith("Asia/Shanghai") || timeZone.startsWith("Asia/Chongqing")) return "china";
  if (timeZone.startsWith("Asia/Seoul")) return "southkorea";
  if (timeZone.startsWith("Asia/Singapore")) return "singapore";
  if (timeZone.startsWith("Australia/")) return "australia";
  return "japan";
}

function validTimeZone(value?: string | null): string {
  const candidate = value?.trim() || "Asia/Tokyo";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: candidate }).format();
    return candidate;
  } catch {
    return "Asia/Tokyo";
  }
}

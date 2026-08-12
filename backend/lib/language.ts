import { headers } from "next/headers";

export type SiteLanguage = "ja" | "en";

export async function preferredLanguage(): Promise<SiteLanguage> {
  const acceptLanguage = (await headers()).get("accept-language")?.toLowerCase() ?? "";
  return acceptLanguage.startsWith("ja") ? "ja" : "en";
}

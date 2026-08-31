import { LandingPage } from "@/app/_components/landing-page";
import type { SiteLanguage } from "@/lib/language";

export default async function LocalizedHome({ params }: { params: Promise<{ lang: SiteLanguage }> }) {
  const { lang } = await params;
  return <LandingPage lang={lang === "en" ? "en" : "ja"} />;
}

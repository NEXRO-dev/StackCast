import { LandingPage } from "@/app/_components/landing-page";
import { preferredLanguage } from "@/lib/language";

export default async function Home() {
  return <LandingPage lang={await preferredLanguage()} />;
}

import { redirect } from "next/navigation";
import { preferredLanguage } from "@/lib/language";

export default async function PrivacyRedirect() {
  redirect(`/${await preferredLanguage()}/privacy`);
}

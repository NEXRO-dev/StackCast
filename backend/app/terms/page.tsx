import { redirect } from "next/navigation";
import { preferredLanguage } from "@/lib/language";

export default async function TermsRedirect() {
  redirect(`/${await preferredLanguage()}/terms`);
}

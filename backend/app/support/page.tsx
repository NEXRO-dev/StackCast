import { redirect } from "next/navigation";
import { preferredLanguage } from "@/lib/language";

export default async function SupportRedirect() {
  redirect(`/${await preferredLanguage()}/support`);
}

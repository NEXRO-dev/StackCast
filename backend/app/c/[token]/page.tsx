import { notFound, redirect } from "next/navigation";
import { getPublicCastByToken } from "@/lib/cast/sharing";
import { preferredLanguage } from "@/lib/language";

export const dynamic = "force-dynamic";

export default async function SharedCastRedirect({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!(await getPublicCastByToken(token))) notFound();
  redirect(`/${await preferredLanguage()}/c/${token}`);
}

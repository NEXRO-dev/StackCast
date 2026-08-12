import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getPublicCastByToken } from "@/lib/cast/sharing";
import { PublicCastPage } from "@/lib/public-cast-page";

export const dynamic = "force-dynamic";

export async function generateMetadata({ params }: { params: Promise<{ lang: "ja" | "en"; token: string }> }): Promise<Metadata> {
  const { lang, token } = await params;
  const cast = await getPublicCastByToken(token);
  if (!cast) return { title: lang === "ja" ? "Castが見つかりません | StackCast" : "Cast not found | StackCast" };
  return { title: `${cast.title} | StackCast`, description: cast.summary ?? `${cast.durationMinutes} Cast` };
}

export default async function LocalizedSharedCast({ params }: { params: Promise<{ lang: "ja" | "en"; token: string }> }) {
  const { lang, token } = await params;
  const cast = await getPublicCastByToken(token);
  if (!cast) notFound();
  return <PublicCastPage cast={cast} token={token} language={lang} />;
}

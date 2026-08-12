import { LegalDocument } from "@/lib/legal-document";

export const dynamic = "force-dynamic";

export default async function LocalizedTerms({ params }: { params: Promise<{ lang: "ja" | "en" }> }) {
  const { lang } = await params;
  const isJapanese = lang !== "en";
  return <LegalDocument language={lang} title={isJapanese ? "StackCast 利用規約" : "StackCast Terms of Service"} fileName="terms_of_service.txt" />;
}

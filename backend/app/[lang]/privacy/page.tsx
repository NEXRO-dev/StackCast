import { LegalDocument } from "@/lib/legal-document";

export const dynamic = "force-dynamic";

export default async function LocalizedPrivacy({ params }: { params: Promise<{ lang: "ja" | "en" }> }) {
  const { lang } = await params;
  const isJapanese = lang !== "en";
  return <LegalDocument language={lang} title={isJapanese ? "StackCast プライバシーポリシー" : "StackCast Privacy Policy"} fileName="privacy_policy.txt" />;
}

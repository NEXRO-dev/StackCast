import Link from "next/link";
import type { SiteLanguage } from "@/lib/language";

export default async function LocalizedHome({ params }: { params: Promise<{ lang: SiteLanguage }> }) {
  const { lang } = await params;
  const isJapanese = lang !== "en";
  return (
    <main className="mx-auto flex min-h-screen w-full max-w-5xl flex-col justify-between px-5 py-10 sm:px-8 sm:py-16">
      <div>
        <nav className="flex items-center justify-between">
          <Link href={`/${lang}`} className="text-xl font-semibold tracking-tight text-zinc-950">StackCast</Link>
          <div className="flex gap-4 text-sm text-zinc-600">
            <Link href={`/${isJapanese ? "en" : "ja"}`}>{isJapanese ? "English" : "日本語"}</Link>
            <Link href={`/${lang}/support`}>{isJapanese ? "サポート" : "Support"}</Link>
          </div>
        </nav>
        <section className="max-w-2xl py-24 sm:py-32">
          <p className="mb-5 text-sm font-medium uppercase tracking-[0.2em] text-zinc-500">Listen to what matters</p>
          <h1 className="text-4xl font-semibold tracking-tight text-zinc-950 sm:text-6xl">
            {isJapanese ? "保存したURLを、耳で聴けるCastに。" : "Turn saved URLs into Casts you can listen to."}
          </h1>
          <p className="mt-7 max-w-xl text-lg leading-8 text-zinc-600">
            {isJapanese
              ? "StackCastは、気になったWebページを保存し、選択した記事をAIで要約して音声で聴けるアプリです。"
              : "StackCast saves the Web pages that matter to you and turns selected articles into AI-generated audio Casts."}
          </p>
          <div className="mt-9 flex flex-wrap gap-3">
            <Link href={`/${lang}/support`} className="rounded-full bg-zinc-950 px-5 py-3 font-medium text-white hover:bg-zinc-700">{isJapanese ? "サポート" : "Support"}</Link>
            <Link href={`/${lang}/privacy`} className="rounded-full border border-zinc-300 px-5 py-3 font-medium text-zinc-800 hover:bg-zinc-100">{isJapanese ? "プライバシーポリシー" : "Privacy Policy"}</Link>
          </div>
        </section>
      </div>
      <footer className="flex flex-wrap gap-x-5 gap-y-2 border-t border-zinc-200 pt-6 text-sm text-zinc-500">
        <Link href={`/${lang}/terms`}>{isJapanese ? "利用規約" : "Terms of Service"}</Link>
        <Link href={`/${lang}/privacy`}>{isJapanese ? "プライバシーポリシー" : "Privacy Policy"}</Link>
        <Link href={`/${lang}/support`}>{isJapanese ? "サポート" : "Support"}</Link>
      </footer>
    </main>
  );
}

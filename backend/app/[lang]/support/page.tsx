import Link from "next/link";

export default async function LocalizedSupport({ params }: { params: Promise<{ lang: "ja" | "en" }> }) {
  const { lang } = await params;
  const isJapanese = lang !== "en";
  return (
    <main className="mx-auto w-full max-w-3xl px-5 py-10 sm:px-8 sm:py-16">
      <div className="mb-12 flex justify-end gap-4 text-sm text-zinc-600">
        <Link href={`/${isJapanese ? "en" : "ja"}/support`}>{isJapanese ? "English" : "日本語"}</Link>
        <Link href={`/${lang}`}>{isJapanese ? "StackCast" : "Home"}</Link>
      </div>
      <h1 className="mb-4 text-3xl font-semibold tracking-tight text-zinc-950 sm:text-4xl">{isJapanese ? "StackCast サポート" : "StackCast Support"}</h1>
      <p className="mb-8 leading-8 text-zinc-600">{isJapanese ? "StackCastに関する不具合、アカウント、Cast生成、課金、公開Castの通報についてお問い合わせいただけます。" : "Contact us about bugs, accounts, Cast generation, billing, or reports about public Casts."}</p>
      <a className="inline-flex rounded-full bg-zinc-950 px-5 py-3 font-medium text-white hover:bg-zinc-700" href="mailto:support@stackcast.app">{isJapanese ? "support@stackcast.app に問い合わせる" : "Contact support@stackcast.app"}</a>
      <p className="mt-8 text-sm leading-7 text-zinc-500">{isJapanese ? "問い合わせの際は、発生日時、利用端末、アプリバージョン、対象CastまたはURL、表示されたエラー内容を可能な範囲でお知らせください。" : "Please include the time of the issue, device, app version, relevant Cast or URL, and any displayed error when possible."}</p>
    </main>
  );
}

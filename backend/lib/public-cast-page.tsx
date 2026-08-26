import type { PublicCast } from "@/lib/cast/sharing";

const appStoreURL = "https://apps.apple.com/jp/app/stackcast/id6799161894";

export function PublicCastPage({ cast: _cast, token: _token, language }: { cast: PublicCast; token: string; language: "ja" | "en" }) {
  const isJapanese = language === "ja";
  return (
    <main className="min-h-screen bg-[radial-gradient(circle_at_top,#ede9fe_0,#f8fafc_42%,#fff_100%)] px-5 py-12 text-slate-950 sm:py-20">
      <section className="mx-auto flex max-w-lg flex-col items-center rounded-[2rem] border border-white/80 bg-white/75 p-8 text-center shadow-[0_24px_80px_rgba(76,29,149,0.14)] backdrop-blur-xl sm:p-12">
        <div className="mb-7 grid size-28 place-items-center rounded-[2rem] bg-gradient-to-br from-indigo-500 to-fuchsia-500 shadow-xl shadow-purple-300/40 sm:size-36">
          <svg aria-hidden="true" viewBox="0 0 120 120" className="size-16 fill-none stroke-white sm:size-20">
            {[34, 22, 48, 70, 52, 30, 42].map((height, index) => <line key={index} x1={24 + index * 12} x2={24 + index * 12} y1={60 - height / 2} y2={60 + height / 2} strokeWidth="7" strokeLinecap="round" />)}
          </svg>
        </div>
        <p className="mb-3 text-sm font-semibold tracking-wide text-indigo-600">StackCast</p>
        <h1 className="text-2xl font-bold leading-tight tracking-tight sm:text-3xl">{isJapanese ? "このCastを聴くには" : "Listen to this Cast"}</h1>
        <p className="mt-4 leading-7 text-slate-600">{isJapanese ? "StackCastアプリで共有されたCastをお楽しみください。" : "Open StackCast to listen to this shared Cast."}</p>
        <a href={appStoreURL} className="mt-8 inline-flex min-h-12 w-full items-center justify-center rounded-full bg-slate-950 px-6 font-semibold text-white transition hover:bg-indigo-700">{isJapanese ? "StackCastをダウンロード" : "Download StackCast"}</a>
        <p className="mt-5 text-xs leading-5 text-slate-400">{isJapanese ? "アプリをインストール後、もう一度このリンクを開くとCastが表示されます。" : "After installing the app, open this link again to view the Cast."}</p>
      </section>
    </main>
  );
}

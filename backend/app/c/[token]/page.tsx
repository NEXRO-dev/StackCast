import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getPublicCastByToken } from "@/lib/cast/sharing";

export const dynamic = "force-dynamic";

type PageProps = { params: Promise<{ token: string }> };

export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { token } = await params;
  const cast = await getPublicCastByToken(token);
  if (!cast) return { title: "Castが見つかりません | StashCast" };

  return {
    title: `${cast.title} | StashCast`,
    description: cast.summary ?? `${cast.durationMinutes}分のCastを聴く`,
    openGraph: {
      title: cast.title,
      description: cast.summary ?? `${cast.durationMinutes}分のCast`,
      type: "music.song",
    },
  };
}

export default async function SharedCastPage({ params }: PageProps) {
  const { token } = await params;
  const cast = await getPublicCastByToken(token);
  if (!cast) notFound();

  return (
    <main className="min-h-screen bg-[radial-gradient(circle_at_top,#ede9fe_0,#f8fafc_42%,#fff_100%)] px-5 py-12 text-slate-950 sm:py-20">
      <section className="mx-auto flex max-w-lg flex-col items-center rounded-[2rem] border border-white/80 bg-white/75 p-6 shadow-[0_24px_80px_rgba(76,29,149,0.14)] backdrop-blur-xl sm:p-10">
        <div className="mb-7 grid size-40 place-items-center rounded-[2rem] bg-gradient-to-br from-indigo-500 to-fuchsia-500 shadow-xl shadow-purple-300/40 sm:size-48">
          <svg aria-hidden="true" viewBox="0 0 120 120" className="size-20 fill-none stroke-white sm:size-24">
            {[34, 22, 48, 70, 52, 30, 42].map((height, index) => (
              <line
                key={index}
                x1={24 + index * 12}
                x2={24 + index * 12}
                y1={60 - height / 2}
                y2={60 + height / 2}
                strokeWidth="7"
                strokeLinecap="round"
              />
            ))}
          </svg>
        </div>

        <p className="mb-2 text-sm font-semibold tracking-wide text-indigo-600">StashCast</p>
        <h1 className="text-center text-2xl font-bold leading-tight tracking-tight sm:text-3xl">{cast.title}</h1>
        <p className="mt-3 text-sm font-medium text-slate-500">{cast.durationMinutes}分のCast</p>

        {cast.summary && <p className="mt-6 text-pretty text-center leading-7 text-slate-600">{cast.summary}</p>}

        <audio className="mt-8 w-full" controls preload="metadata" src={`/api/public/casts/${token}/audio`}>
          お使いのブラウザは音声再生に対応していません。
        </audio>

        <a
          href={`stashcast://cast/${token}`}
          className="mt-8 inline-flex min-h-12 w-full items-center justify-center rounded-full bg-slate-950 px-6 font-semibold text-white transition hover:bg-indigo-700"
        >
          StashCastで開く
        </a>
        <p className="mt-5 text-center text-xs leading-5 text-slate-400">
          共有されたCastだけを再生します。文字起こしや作成者の個人情報は公開されません。
        </p>
      </section>
    </main>
  );
}

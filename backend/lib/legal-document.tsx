import fs from "node:fs";
import path from "node:path";

function readDocument(fileName: string): string {
  const candidates = [
    path.join(process.cwd(), "public", "legal", fileName),
    path.join(process.cwd(), fileName),
    path.join(process.cwd(), "..", fileName),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return fs.readFileSync(candidate, "utf8");
    }
  }

  return "この文書は現在準備中です。最新の内容はアプリ内の表示をご確認ください。";
}

export function LegalDocument({ title, fileName, language = "ja" }: { title: string; fileName: string; language?: "ja" | "en" }) {
  const localizedFileName = language === "en" ? fileName.replace(".txt", "_en.txt") : fileName;
  const content = readDocument(localizedFileName).replace(
    /^(.*?\n)?制定日：[^\n]*\n最終更新日：[^\n]*\n\n?/u,
    "$1",
  );

  return (
    <main className="mx-auto w-full max-w-4xl px-5 py-10 sm:px-8 sm:py-16">
      <h1 className="mb-8 text-3xl font-semibold tracking-tight text-zinc-950 sm:text-4xl">{title}</h1>
      <article className="whitespace-pre-wrap break-words rounded-2xl border border-zinc-200 bg-white p-5 text-[15px] leading-8 text-zinc-700 shadow-sm sm:p-10">
        {content}
      </article>
    </main>
  );
}

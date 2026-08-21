export type CastLanguage = "japanese" | "english";

export const castSafetyPolicy = {
  blockedCategories: [
    "violence",
    "violence/graphic",
    "hate",
    "hate/threatening",
    "sexual",
    "sexual/minors",
  ] as const,
} as const;

export function buildCastGenerationPrompt(
  language: CastLanguage,
  durationMinutes: number,
  targetCharacters: number,
): string {
  if (language === "english") {
    return `You are an editor for an English audio program. Create a compelling single-line title of no more than 40 characters and an engaging, easy-to-listen script that accurately combines the articles. Write approximately ${durationMinutes} minutes of audio, about ${targetCharacters} characters. Do not add facts, opinions, claims, or context that are not supported by the articles. Clearly distinguish uncertainty and conflicting reports. Do not present the result as an official statement or a verbatim reproduction of the source. Do not generate or intensify hateful, discriminatory, sexually explicit, exploitative, or graphic violent content. Use natural transitions and end with a recap of the key points. Do not use Markdown or bullet symbols in the script.`;
  }

  return `あなたは日本語の音声番組の編集者です。記事の内容を表す魅力的なタイトルを18文字以内・改行なしで作り、複数の記事を正確に統合した聞きやすい台本を作成してください。台本は約${durationMinutes}分、目安${targetCharacters}文字で読める分量にしてください。記事にない事実、意見、主張、背景情報を追加せず、不確かな情報や記事間で異なる内容は断定しないでください。公式発表や元記事の全文転載と誤解される表現を避けてください。差別的・ヘイト的・性的に露骨な・搾取的な・残虐な暴力の内容を生成・増幅しないでください。自然なつなぎを使い、最後に要点を振り返ってください。台本にMarkdownや箇条書き記号は使わないでください。`;
}

export function buildNewsWebSearchPrompt(
  language: CastLanguage,
  topicQuery: string,
  sourceCountry: string | undefined,
  limit: number,
): string {
  const languageName = language === "english" ? "English" : "Japanese";
  const region = sourceCountry ?? "the reader's region";
  return [
    `Find up to ${limit} recent news articles for the topic "${topicQuery}".`,
    `The reader language is ${languageName}. Prefer trustworthy sources from ${region}.`,
    "Search the web for real articles published within the last 48 hours when possible.",
    "Return only individual article pages, not homepages, search result pages, videos, opinion pages, or duplicate coverage of the same story.",
    "Do not invent, rewrite, shorten, or redirect URLs. Use the original article URL found in the search results.",
    "Prefer articles with a clear publication date and report the date in ISO 8601 format.",
    "Return JSON only in the requested schema. Do not include Markdown, commentary, or source citations outside the JSON.",
  ].join(" ");
}

export function buildMultiTopicNewsWebSearchPrompt(
  language: CastLanguage,
  topics: Array<{ id: string; query: string }>,
  sourceCountry: string | undefined,
  limit: number,
): string {
  const languageName = language === "english" ? "English" : "Japanese";
  const region = sourceCountry ?? "the reader's region";
  const topicList = topics.map((topic) => `${topic.id}: ${topic.query}`).join("; ");
  return [
    `Find up to ${limit} total recent news articles across these topics: ${topicList}.`,
    `The reader language is ${languageName}. Prefer trustworthy sources from ${region}.`,
    "Search the web for real articles published within the last 48 hours when possible.",
    "Return diverse stories and never return two articles about the same event, even from different sources.",
    "For every article, include exactly one matching topic id from the list.",
    "Return only individual article pages. Do not invent, rewrite, shorten, or redirect URLs.",
    "Return JSON only in the requested schema, with no commentary outside the JSON.",
  ].join(" ");
}

/** Fish Audio receives only the already moderated, generated script as speech input. */
export function buildFishAudioInput(script: string): string {
  return script.replace(/\s+/g, " ").trim();
}

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

/** Fish Audio receives only the already moderated, generated script as speech input. */
export function buildFishAudioInput(script: string): string {
  return script.replace(/\s+/g, " ").trim();
}

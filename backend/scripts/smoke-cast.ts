import { HeadObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { createCast } from "../lib/cast/pipeline";
import { getTurso } from "../lib/turso";

const database = getTurso();
const user = (await database.get(
  "SELECT id FROM users ORDER BY created_at ASC LIMIT 1",
)) as { id?: string } | null;

if (!user?.id) {
  throw new Error("Smoke test requires at least one registered user.");
}

const cast = await createCast(user.id, {
  title: "StashCast 接続テスト",
  durationMinutes: 5,
  sources: [
    {
      url: "https://example.com/stashcast-test/product",
      title: "音声で情報を振り返る価値",
      text: "忙しい日には、保存した記事を読み返す時間を確保することが難しい。移動中や家事の時間に要点を音声で聞ければ、後回しになっていた情報を生活の中で自然に振り返れる。大切なのは単なる短縮ではなく、複数の記事の関係が分かる順序で整理することである。",
    },
    {
      url: "https://example.com/stashcast-test/quality",
      title: "要約音声の品質を保つ方法",
      text: "良い要約では、元の記事にない情報を加えず、重要な前提と結論を残す必要がある。音声向けの文章では、長すぎる一文を避け、話題が変わる場所に自然なつなぎを入れる。出典となる記事ごとの違いを消さずに、一つの番組として聞ける構成にすることが品質につながる。",
    },
    {
      url: "https://example.com/stashcast-test/storage",
      title: "生成した音声を安全に保存する設計",
      text: "生成したMP3はオブジェクトストレージに保存し、データベースにはファイル本体ではなくオブジェクトキーを記録する。再生時には期限付きURLを発行することで、バケットを公開せずにアプリから音声を取得できる。生成状態と失敗理由も記録すれば、再試行やユーザーへの案内が行いやすい。",
    },
  ],
});

if (cast.status !== "completed" || !cast.audioObjectKey || !cast.audioURL) {
  throw new Error(`Cast did not complete successfully: ${cast.status}`);
}

const r2 = new S3Client({
  region: "auto",
  endpoint: requiredEnvironmentVariable("R2_ENDPOINT"),
  credentials: {
    accessKeyId: requiredEnvironmentVariable("R2_ACCESS_KEY_ID"),
    secretAccessKey: requiredEnvironmentVariable("R2_SECRET_ACCESS_KEY"),
  },
});
const object = await r2.send(
  new HeadObjectCommand({
    Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"),
    Key: cast.audioObjectKey,
  }),
);

const persisted = (await database.get(
  `SELECT casts.status AS castStatus,
          casts.audio_object_key AS audioObjectKey,
          cast_generation_jobs.status AS jobStatus
   FROM casts
   JOIN cast_generation_jobs ON cast_generation_jobs.cast_id = casts.id
   WHERE casts.id = ? AND casts.user_id = ?
   LIMIT 1`,
  cast.id,
  user.id,
)) as {
  castStatus?: string;
  audioObjectKey?: string;
  jobStatus?: string;
} | null;

if (
  persisted?.castStatus !== "completed" ||
  persisted.jobStatus !== "completed" ||
  persisted.audioObjectKey !== cast.audioObjectKey
) {
  throw new Error("Turso persistence verification failed.");
}

console.log(
  JSON.stringify(
    {
      success: true,
      castID: cast.id,
      castStatus: persisted.castStatus,
      jobStatus: persisted.jobStatus,
      r2ObjectKey: cast.audioObjectKey,
      r2ContentType: object.ContentType,
      r2ContentLength: object.ContentLength,
      signedURLCreated: true,
    },
    null,
    2,
  ),
);

function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

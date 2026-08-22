import { featureEnabled } from "../feature-flags";
import { getTurso } from "../turso";
import { GDELTProvider } from "./providers/gdelt";
import { GroqWebSearchProvider } from "./providers/groq-web-search";
import { OpenAIWebSearchProvider } from "./providers/openai-web-search";
import { upsertNewsCandidate } from "./repository";

type TopicRow = { id: string; query: string };
export const NEWS_POOL_COOLDOWN_MS = 6 * 60 * 60 * 1_000;

export type NewsRefreshOptions = {
  language?: "japanese" | "english";
  sourceCountry?: string;
  topicIDs?: string[];
  excludeTopicIDs?: string[];
  force?: boolean;
};

export type NewsRefreshResult = {
  topics: number;
  fetched: number;
  stored: number;
  failures: string[];
  cooldown: boolean;
};

export type NewsRefreshBuildDecision = {
  forceRebuild: boolean;
  markFallback: boolean;
};

export type NewsErrorDiagnostic = {
  code: string;
  explanationJa: string;
  nextActionJa: string;
};

export function newsRefreshIsWithinCooldown(
  latestSuccessfulFetchAt: string | null | undefined,
  now = new Date(),
  force = false,
  successfulArticleCount = 5,
): boolean {
  if (force || successfulArticleCount < 5 || !latestSuccessfulFetchAt) return false;
  const latestTimestamp = Date.parse(latestSuccessfulFetchAt);
  if (!Number.isFinite(latestTimestamp)) return false;
  const elapsed = now.getTime() - latestTimestamp;
  return elapsed >= 0 && elapsed < NEWS_POOL_COOLDOWN_MS;
}

export function newsRefreshProviderUnavailable(result: NewsRefreshResult): boolean {
  return !result.cooldown && result.stored === 0 && result.failures.length > 0;
}

export function newsRefreshProviderUnderfilled(result: NewsRefreshResult): boolean {
  return !result.cooldown && result.stored > 0 && result.stored < 5;
}

export function newsRefreshBuildDecision(result: NewsRefreshResult): NewsRefreshBuildDecision {
  const markFallback = newsRefreshProviderUnavailable(result) || newsRefreshProviderUnderfilled(result);
  return {
    forceRebuild: result.stored > 0 || markFallback,
    markFallback,
  };
}

/** Groq web search first; GDELT/OpenAI are optional fallback providers. */
export async function refreshSharedNewsPool(options: NewsRefreshOptions = {}): Promise<NewsRefreshResult> {
  const startedAt = Date.now();
  const topicIDs = [...new Set(options.topicIDs ?? [])];
  const filters = ["is_active = 1"];
  const args: string[] = [];
  if (topicIDs.length > 0) {
    filters.push(`id IN (${topicIDs.map(() => "?").join(", ")})`);
    args.push(...topicIDs);
  }
  const excludedTopicIDs = [...new Set(options.excludeTopicIDs ?? [])];
  if (excludedTopicIDs.length > 0) {
    filters.push(`id NOT IN (${excludedTopicIDs.map(() => "?").join(", ")})`);
    args.push(...excludedTopicIDs);
  }
  const topics = (await getTurso().all(
    `SELECT id, query_en AS query FROM recommendation_topics WHERE ${filters.join(" AND ")} ORDER BY sort_order`,
    ...args,
  )) as TopicRow[];
  const language = options.language ?? "japanese";
  const groqEnabled = featureEnabled("GROQ_NEWS_PROVIDER_ENABLED", Boolean(process.env.GROQ_API_KEY?.trim()));
  const gdeltEnabled = featureEnabled("GDELT_PROVIDER_ENABLED", false);
  const openAIEnabled = featureEnabled("OPENAI_NEWS_FALLBACK_ENABLED", false);
  const providerOrder = [
    ...(groqEnabled ? ["Groq"] : []),
    ...(gdeltEnabled ? ["GDELT"] : []),
    ...(openAIEnabled ? ["OpenAI予備"] : []),
  ];
  console.info("[daily-news] ニュース取得の準備完了", {
    provider候補: providerOrder.length > 0 ? providerOrder.join(" → ") : "すべて無効",
    言語: language === "japanese" ? "日本語" : "英語",
    対象国: options.sourceCountry ?? "指定なし",
    ジャンル数: topics.length,
    ジャンル: topics.map((topic) => ({ id: topic.id, 検索語: topic.query })),
    再取得強制: options.force === true,
  });
  const cooldownCutoff = new Date(Date.now() - NEWS_POOL_COOLDOWN_MS).toISOString();
  const latest = (await getTurso().get(
    `SELECT MAX(fetched_at) AS fetchedAt, COUNT(DISTINCT id) AS articleCount FROM news_articles
     WHERE provider IN (?, ?, ?) AND LOWER(language) = LOWER(?)
       AND ((LOWER(country) = LOWER(?) AND ? IS NOT NULL) OR (country IS NULL AND ? IS NULL))
       AND fetched_at >= ?`,
    "groq-web-search", "gdelt", "openai-web-search", language, options.sourceCountry ?? null,
    options.sourceCountry ?? null, options.sourceCountry ?? null, cooldownCutoff,
  )) as { fetchedAt?: string | null; articleCount?: number } | null;
  if (newsRefreshIsWithinCooldown(latest?.fetchedAt, new Date(), options.force, latest?.articleCount ?? 0)) {
    console.info("[daily-news] shared pool refresh skipped", {
      reason: "cooldown", providers: ["groq-web-search", "gdelt", "openai-web-search"], topics: topics.length,
      lastFetchedAt: latest?.fetchedAt, articleCount: latest?.articleCount ?? 0,
      cooldownHours: NEWS_POOL_COOLDOWN_MS / 3_600_000,
      説明_日本語: "直近6時間以内に十分な記事が保存済みのため、同じニュースの重複取得を防止しました。",
      次の動作_日本語: "キャッシュ済み記事を使い、次回の定期処理まで外部APIを呼び出しません。",
    });
    return { topics: topics.length, fetched: 0, stored: 0, failures: [], cooldown: true };
  }

  let fetched = 0;
  let stored = 0;
  const failures: string[] = [];
  console.info("[daily-news] shared pool refresh started", {
    provider: groqEnabled ? "groq-web-search" : gdeltEnabled ? "gdelt" : "disabled",
    fallbackProviders: [
      ...(gdeltEnabled ? ["gdelt"] : []),
      ...(openAIEnabled ? ["openai-web-search"] : []),
    ],
    topics: topics.length,
    language, sourceCountry: options.sourceCountry ?? null,
  });

  if (groqEnabled) {
    const groq = new GroqWebSearchProvider();
    const perTopicLimit = groqPerTopicLimit();
    console.info("[daily-news] Groq候補ニュース取得を開始", {
      説明_日本語: "Groq CompoundのWeb Searchで各ジャンルから複数URLを集め、DB候補プールへ保存します。",
      リクエスト数: topics.length,
      目標候補数_ジャンルごと: perTopicLimit,
      モデル: process.env.GROQ_NEWS_MODEL?.trim() || "groq/compound-mini",
      タイムアウト秒: Number(process.env.GROQ_NEWS_REQUEST_TIMEOUT_MS ?? 45000) / 1000,
    });
    try {
      const candidates = await groq.searchTopics(topics.map((topic) => ({
        topicID: topic.id,
        query: topic.query,
        language,
        sourceCountry: options.sourceCountry,
        limit: perTopicLimit,
      })));
      fetched += candidates.length;
      const groqStored = await storeCandidates(topics[0]?.id ?? "", "groq-web-search", candidates, failures);
      stored += groqStored;
      console.info("[daily-news] groq candidate refresh completed", {
        topics: topics.length,
        fetched: candidates.length,
        stored: groqStored,
        totalStored: stored,
        requests: topics.length,
        説明_日本語: `Groq Web Searchから${candidates.length}件の候補URLを受信し、${groqStored}件をDBへ保存しました。`,
      });
    } catch (error) {
      const details = errorDetails(error);
      const diagnostic = diagnoseNewsError(error);
      failures.push(`groq:${details.message}`);
      console.warn("[daily-news] groq candidate refresh failed", {
        topics: topics.length,
        requests: topics.length,
        ...details,
        エラーコード: diagnostic.code,
        原因_日本語: diagnostic.explanationJa,
        対応_日本語: diagnostic.nextActionJa,
      });
    }
  } else {
    console.info("[daily-news] groq refresh skipped", {
      reason: process.env.GROQ_NEWS_PROVIDER_ENABLED === "false" ? "feature_disabled" : "missing_api_key",
      説明_日本語: "GROQ_API_KEY が未設定、または GROQ_NEWS_PROVIDER_ENABLED=false のため、Groq候補取得を使いません。",
    });
  }

  if (stored < 5 && gdeltEnabled) {
    const gdelt = new GDELTProvider();
    console.info("[daily-news] GDELT取得を開始", {
      説明_日本語: "Groqだけでは5件に届かなかったため、無料公開のGDELTで補完します。",
      リクエスト数: 1,
      タイムアウト秒: Number(process.env.GDELT_REQUEST_TIMEOUT_MS ?? 15000) / 1000,
      最小リクエスト間隔秒: Number(process.env.GDELT_MIN_REQUEST_INTERVAL_MS ?? 6000) / 1000,
    });
    try {
      const candidates = await gdelt.searchTopics(topics.map((topic) => ({
        topicID: topic.id,
        query: topic.query,
        language,
        sourceCountry: options.sourceCountry,
        limit: 5,
      })));
      fetched += candidates.length;
      const gdeltStored = await storeCandidates(topics[0]?.id ?? "", "gdelt", candidates, failures);
      stored += gdeltStored;
      console.info("[daily-news] gdelt combined refresh completed", {
        topics: topics.length,
        fetched: candidates.length,
        requests: 1,
        stored: gdeltStored,
        totalStored: stored,
        説明_日本語: `GDELTから${candidates.length}件を受信し、${gdeltStored}件をDBへ保存しました。`,
      });
    } catch (error) {
      const details = errorDetails(error);
      const diagnostic = diagnoseNewsError(error);
      failures.push(`combined:gdelt:${details.message}`);
      console.warn("[daily-news] gdelt combined refresh failed", {
        topics: topics.length,
        requests: 1,
        ...details,
        エラーコード: diagnostic.code,
        原因_日本語: diagnostic.explanationJa,
        対応_日本語: diagnostic.nextActionJa,
      });
    }
  } else if (stored >= 5) {
    console.info("[daily-news] gdelt refresh skipped", {
      reason: "already_filled_by_groq",
      説明_日本語: "Groq候補取得で5件以上そろったため、GDELTは呼び出しません。",
    });
  } else {
    console.info("[daily-news] gdelt refresh skipped", {
      reason: "feature_disabled",
      説明_日本語: "GDELT_PROVIDER_ENABLED が true ではないため、GDELTを使わず次の予備取得へ進みます。",
    });
  }

  if (stored < 5 && openAIEnabled) {
    console.info("[daily-news] OpenAI予備取得を開始", {
      理由_日本語: `Groq/GDELTだけでは5件に届かなかったため（現在${stored}件）、不足分を補完します。`,
      対象ジャンル数: topics.length,
      リトライ回数: 1,
    });
    try {
      const fallback = new OpenAIWebSearchProvider();
      const candidates = await fallback.searchTopics(topics.map((topic) => ({
        topicID: topic.id, query: topic.query, language,
        sourceCountry: options.sourceCountry, limit: 5,
      })));
      fetched += candidates.length;
      stored += await storeCandidates(topics[0]?.id ?? "", "openai-web-search", candidates, failures);
      console.info("[daily-news] openai fallback refreshed", {
        fetched: candidates.length,
        stored,
        reason: groqEnabled ? "groq_underfilled" : gdeltEnabled ? "gdelt_underfilled" : "primary_provider_disabled",
        説明_日本語: `OpenAI Web Searchから${candidates.length}件を受信し、合計${stored}件をDBへ保存しました。`,
      });
    } catch (error) {
      const details = errorDetails(error);
      const diagnostic = diagnoseNewsError(error);
      failures.push(`openai-fallback:${details.message}`);
      console.warn("[daily-news] openai fallback failed", {
        ...details,
        エラーコード: diagnostic.code,
        原因_日本語: diagnostic.explanationJa,
        対応_日本語: diagnostic.nextActionJa,
      });
    }
  } else if (stored >= 5) {
    console.info("[daily-news] OpenAI予備取得をスキップ", {
      説明_日本語: "GroqまたはGDELTで5件以上そろったため、OpenAIの追加利用を抑止しました。",
    });
  } else {
    console.info("[daily-news] OpenAI予備取得を無効化", {
      説明_日本語: "OPENAI_NEWS_FALLBACK_ENABLED=true が明示されていないため、不足分のOpenAI Web Search補完を行いません。",
    });
  }

  const result: NewsRefreshResult = {
    topics: topics.length,
    fetched,
    stored,
    failures: failures.slice(0, 50),
    cooldown: false,
  };
  console.info("[daily-news] shared pool refresh completed", {
    ...result,
    failureCount: failures.length,
    所要時間Ms: Date.now() - startedAt,
    結果_日本語: stored >= 5
      ? "5件以上の記事を確保しました。"
      : stored > 0
        ? `一部成功です。${stored}件のみ確保したため、DBキャッシュを使って補完します。`
        : "外部APIから記事を取得できませんでした。既存キャッシュを使って処理を継続します。",
    失敗一覧_日本語: failures.map((failure) => ({
      raw: failure,
      説明: diagnoseNewsError(new Error(failure)).explanationJa,
    })),
  });
  return result;
}

function groqPerTopicLimit(): number {
  const requested = Number(process.env.GROQ_NEWS_PER_TOPIC_LIMIT);
  if (!Number.isFinite(requested)) return 12;
  return Math.min(Math.max(Math.round(requested), 1), 20);
}

async function storeCandidates(
  defaultTopicID: string,
  provider: string,
  candidates: Array<Parameters<typeof upsertNewsCandidate>[2]>,
  failures: string[],
): Promise<number> {
  let stored = 0;
  for (const candidate of candidates) {
    const topicID = candidate.topicID ?? defaultTopicID;
    if (!topicID) {
      console.warn("[daily-news] 記事を保存せずスキップ", {
        理由_日本語: "記事にジャンルIDが付いていないため、ユーザーの興味と紐付けられません。",
        provider,
        title: candidate.title,
      });
      continue;
    }
    try {
      await upsertNewsCandidate(topicID, provider, candidate);
      stored += 1;
      console.info("[daily-news] 記事をDBへ保存", {
        provider,
        topicID,
        source: candidate.sourceDomain,
        publishedAt: candidate.publishedAt,
        説明_日本語: "取得記事を正規化し、同一URLは重複登録せず保存しました。",
      });
    } catch (error) {
      const diagnostic = diagnoseNewsError(error);
      const message = error instanceof Error ? error.message : String(error);
      failures.push(`${topicID}:${provider}:store:${message}`);
      console.error("[daily-news] 記事のDB保存に失敗", {
        provider,
        topicID,
        エラーコード: diagnostic.code,
        原因_日本語: diagnostic.explanationJa,
        対応_日本語: diagnostic.nextActionJa,
      });
    }
  }
  return stored;
}

function errorDetails(error: unknown): { name: string; message: string; cause?: string } {
  if (!(error instanceof Error)) return { name: "UnknownError", message: String(error) };
  const cause = error.cause instanceof Error ? `${error.cause.name}: ${error.cause.message}` : error.cause ? String(error.cause) : undefined;
  return { name: error.name, message: error.message, ...(cause ? { cause } : {}) };
}

export function diagnoseNewsError(error: unknown): NewsErrorDiagnostic {
  const details = errorDetails(error);
  const raw = `${details.message} ${details.cause ?? ""}`.toLowerCase();
  if (raw.includes("429") || raw.includes("rate_limit")) {
    return {
      code: "HTTP_429_RATE_LIMIT",
      explanationJa: "アクセス過多または利用上限により、ニュース提供元がリクエストを拒否しました。APIキーの有無だけでなく、短時間の呼び出し集中や利用枠も確認が必要です。",
      nextActionJa: "この実行中に連続再試行せず、クールダウン後の次回処理で再取得します。保存済みキャッシュがあればそれを表示します。",
    };
  }
  if (raw.includes("circuit_open") || raw.includes("temporarily_unavailable")) {
    return {
      code: "PROVIDER_CIRCUIT_OPEN",
      explanationJa: "直前のタイムアウトまたは429を検知したため、同じ実行内の追加リクエストを安全のため停止しました。",
      nextActionJa: "APIをさらに叩かず、クールダウン終了後の次回定期処理で再開します。",
    };
  }
  if (raw.includes("timeout") || raw.includes("aborted") || raw.includes("connect_timeout")) {
    return {
      code: "NETWORK_TIMEOUT",
      explanationJa: "ニュース提供元から設定時間内に応答が返らず、接続を中断しました。提供元の混雑、ネットワーク経路、検索条件の重さが候補です。",
      nextActionJa: "同じリクエストを即時に繰り返さず、別プロバイダーまたはDBキャッシュへ切り替えます。",
    };
  }
  if (raw.includes("missing required environment variable") || raw.includes("api_key")) {
    return {
      code: "CONFIGURATION_ERROR",
      explanationJa: "ニュース取得に必要な環境変数またはAPIキーが設定されていません。",
      nextActionJa: "サーバー環境のGROQ_API_KEYやOPENAI_API_KEYなどを確認し、キー自体はログへ出力しないで設定します。",
    };
  }
  return {
    code: details.name || "UNKNOWN_ERROR",
    explanationJa: `ニュース取得処理で予期しないエラーが発生しました（${details.message}）。`,
    nextActionJa: "エラーコード・発生時刻・対象ジャンルを確認し、キャッシュ表示を維持したまま次回処理で再試行します。",
  };
}

# StackCast パーソナルニュース実装計画

## 実装状況（2026年8月19日）

初期リリース用の縦切り実装は完了した。

- 完了：Turso migration 014、9ジャンル、共通記事プール、GDELT Provider、URL正規化・重複排除
- 完了：ユーザー別プロフィール、3ジャンル以上の初回設定、毎日の5件、推薦理由、前日fallback
- 完了：impression／open／dwell／save／dislikeイベントと説明可能なトピックメモリ、個別削除・リセット
- 完了：Plus／Pro向け自動Cast設定、AI同意、直近利用判定、Queue、lease、最大3回の再試行
- 完了：iOSホーム、記事閲覧・保存・興味なし、アカウント内ジャンル表示・編集・メモリ管理
- 完了：午前1時JSTのVercel Cron、環境Feature Flag、Adminの候補・日次版・Queue監視
- 完了：日英プライバシー文書への推薦データ、GDELT、自動Cast、保持・削除範囲の反映
- 検証済み：migration 001〜014、Backendテスト、本番Backend/Adminビルド、iOS汎用端末ビルド

本番デプロイ後に行う運用検証：GDELT実通信、午前1時Cron、対象を限定したOpenAI/Fish Audio/R2の自動Cast実データ確認。記事単位のAI要約共有キャッシュ、端末内オフラインイベント再送、年代別匿名トレンド、Adminからの手動再実行は次段階とする。年代別トレンドは最低20人の条件を満たすまで公開しない。

## 1. 目的

StackCastの主機能を「保存済みURLからCastを作る」から、次の体験へ段階的に変更する。

```text
初回に興味ジャンルを選ぶ
  → 毎日午前1時に自分向けニュース5件が確定する
  → ホームに「今日の5件」が届く
  → 読む／保存／興味なし／Cast候補へ追加
  → 行動がメモリへ反映される
  → 次の推薦が改善される
  → Plus／Proは任意で5件をまとめたデイリーCastを受け取る
  → 保存記事や任意URLからCastを生成する
```

既存のURL保存、Share Extension、Cast生成、課金、再生、Live Activityは維持する。新機能はFeature Flagの内側で追加し、既存ユーザーを止めずに導入する。

## 2. 基本方針

1. GDELTはニュース候補の取得元として使い、推薦順位はStackCast側で決める。
2. iOSからGDELTを直接呼ばず、バックエンドを経由する。
3. 明示的なジャンル選択を推薦の初期値にする。
4. 閲覧しただけで強い好みと判断せず、保存、滞在、興味なし、Cast化など複数の信号を使う。
5. メモリはユーザー本人が確認、編集、削除、無効化できる。
6. 年代は範囲で扱い、性別は任意回答とする。性別は推薦v1の順位付けには使わない。
7. 年代別トレンドは匿名集計だけを表示し、最低集計人数に達するまで機能を非表示にする。
8. 推薦が失敗しても、保存記事・Cast・汎用ニュースは引き続き利用できる。
9. 選択ジャンルはアカウント画面にチップとして常時表示し、そこから編集できる。
10. ニュース候補取得はユーザー単位で行わず、全ユーザー共通の記事プールを定期更新する。
11. ホームはユーザー別に確定した「今日の5件」を表示し、日中の再読み込みではGDELTを呼ばない。
12. 毎日午前1時（`Asia/Tokyo`）のバッチで、共通候補取得、ユーザー別5件選定、対象ユーザーのデイリーCast生成を開始する。
13. 推薦表示だけではOpenAIやFish Audioを呼ばず、従量コストが発生するAI処理はCast生成時に限定する。
14. デイリーCastは5記事を別々に生成せず、5件をまとめた1本を1日1回生成する。
15. デイリーCastはPlus／Pro、設定ON、AI同意済み、直近7日以内に利用、有効クレジットありのユーザーだけを対象とする。
16. 記事単位の要約を共有キャッシュし、同じ記事へのOpenAI処理をユーザーごとに重複させない。

## 3. 目標アーキテクチャ

```text
GDELT DOC 2.0
      │
      ▼
News Provider Adapter ── Canonicalizer / Deduplicator
      │
      ▼
news_articles / news_article_topics
      │
      ▼ 毎日 01:00 Asia/Tokyo
Daily Edition Builder
      │
      ├── Explicit preferences
      ├── User memory
      ├── Recommendation events
      └── Freshness / diversity / quality
      │
      ▼
Recommendation Ranker
      │
      ▼
Daily 5 Items / Feed Cache ── GET /api/recommendations/feed
      │
      ├── iOS Home Feed
      └── Eligible user → Daily Cast Queue
                              │
                              ├── Shared article summaries
                              ├── Daily script
                              ├── Fish Audio
                              └── R2 / casts
      │
      ├── open
      ├── save
      ├── dislike
      └── add_to_cast
      │
      ▼
Event API ── Memory Aggregator ── 次回ランキング
```

### 3.1 既存構成との対応

| 層 | 現在 | 追加するもの |
| --- | --- | --- |
| iOS | SwiftUI、`AuthStore`、`ArticleLibrary`、`CastStore` | `RecommendationStore`、`MemoryStore`、オンボーディング、ホームフィード |
| Backend | Next.js API Routes | News Provider、日次Batch、Queue Worker、Feed、Events、Profile、Memory、Trends API |
| DB | Turso / SQLite、連番SQL migration | 推薦プロフィール、記事候補、イベント、メモリ、日次5件、要約キャッシュ、生成ジョブ |
| Admin | Next.js管理画面 | Feature Flag、Provider状態、日次Batch・Queue状態、集計、推薦デバッグ |
| 外部 | OpenAI、Fish Audio、R2、RevenueCat | GDELT DOC 2.0、将来の代替ニュースProvider |

## 4. DB設計

既存の `users` を肥大化させず、パーソナライズ関連は別テーブルへ分離する。新規migrationは `014_personal_news_core.sql` から開始する。

### 4.1 `recommendation_topics`

運営側が管理するジャンルマスター。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `id` | TEXT PK | `technology` などの固定ID |
| `name_ja` | TEXT | 日本語名 |
| `name_en` | TEXT | 英語名 |
| `query_en` | TEXT | GDELT検索用英語クエリ |
| `is_active` | INTEGER | 表示・取得対象 |
| `sort_order` | INTEGER | オンボーディング表示順 |
| `created_at` | TEXT | 作成日時 |
| `updated_at` | TEXT | 更新日時 |

初期ジャンル：technology、business、science、entertainment、sports、society、world、health、culture。

### 4.2 `user_recommendation_profiles`

ユーザーごとの推薦設定。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `user_id` | TEXT PK / FK | `users.id` |
| `age_band` | TEXT | 年代範囲、未回答可 |
| `gender` | TEXT NULL | 任意回答、`prefer_not_to_say`を含む |
| `personalization_enabled` | INTEGER | パーソナライズ利用可否 |
| `daily_auto_cast_enabled` | INTEGER | Plus／Pro向け日次Cast自動生成 |
| `daily_cast_duration_minutes` | INTEGER | 初期値5分、プラン上限内 |
| `onboarding_completed_at` | TEXT NULL | 初回設定完了 |
| `memory_version` | INTEGER | 集計ロジック更新用 |
| `created_at` | TEXT | 作成日時 |
| `updated_at` | TEXT | 更新日時 |

推奨年代値：`under_18`、`18_24`、`25_34`、`35_44`、`45_54`、`55_plus`、`unspecified`。

### 4.3 `user_topic_preferences`

初回選択とユーザーが後から編集した明示的な興味。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `user_id` | TEXT FK | ユーザー |
| `topic_id` | TEXT FK | ジャンル |
| `preference` | TEXT | `like` / `neutral` / `avoid` |
| `weight` | REAL | 0〜1 |
| `source` | TEXT | `onboarding` / `manual` |
| `created_at` | TEXT | 作成日時 |
| `updated_at` | TEXT | 更新日時 |

主キーは `(user_id, topic_id)`。

### 4.4 `news_articles`

GDELT等から取得した記事候補の正規化キャッシュ。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `id` | TEXT PK | UUID |
| `canonical_url` | TEXT UNIQUE | 正規化済みURL |
| `original_url` | TEXT | Providerが返したURL |
| `title` | TEXT | 記事タイトル |
| `description` | TEXT NULL | 短い説明 |
| `image_url` | TEXT NULL | サムネイル |
| `source_domain` | TEXT | 媒体ドメイン |
| `language` | TEXT | 言語 |
| `country` | TEXT NULL | 国 |
| `published_at` | TEXT | 公開日時 |
| `provider` | TEXT | `gdelt` など |
| `provider_id` | TEXT NULL | Provider上の識別子 |
| `content_hash` | TEXT NULL | 同内容重複排除 |
| `quality_score` | REAL | 0〜1 |
| `fetched_at` | TEXT | 取得日時 |
| `expires_at` | TEXT | キャッシュ期限 |

`canonical_url`、`published_at`、`source_domain`、`expires_at` にindexを作る。

### 4.5 `news_article_topics`

記事とジャンルの対応。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `article_id` | TEXT FK | 記事 |
| `topic_id` | TEXT FK | ジャンル |
| `score` | REAL | 関連度 |
| `source` | TEXT | Providerまたは分類器 |

主キーは `(article_id, topic_id)`。

### 4.6 `recommendation_events`

ユーザー行動の追記専用イベント。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `id` | TEXT PK | クライアント生成UUID、再送時の冪等性に使用 |
| `user_id` | TEXT FK | ユーザー |
| `article_id` | TEXT FK | 記事 |
| `event_type` | TEXT | 下記イベント種別 |
| `surface` | TEXT | `home` / `stock` / `cast` |
| `session_id` | TEXT | フィードセッション |
| `dwell_ms` | INTEGER NULL | 滞在時間 |
| `position` | INTEGER NULL | 表示順位 |
| `metadata_json` | TEXT NULL | 将来拡張 |
| `occurred_at` | TEXT | 端末上の発生日時 |
| `received_at` | TEXT | サーバー受信日時 |

イベント種別：`impression`、`open`、`dwell`、`save`、`unsave`、`dislike`、`mute_topic`、`mute_source`、`add_to_cast`、`cast_created`、`cast_completed`。

`(user_id, occurred_at)`、`(article_id, event_type)`、`received_at` にindexを作る。

### 4.7 `user_memory_items`

イベントから集計した説明可能な推薦メモリ。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK | ユーザー |
| `kind` | TEXT | `topic` / `source` / `keyword` |
| `value` | TEXT | topic ID、domain、keyword |
| `polarity` | TEXT | `positive` / `negative` |
| `weight` | REAL | 0〜1 |
| `origin` | TEXT | `explicit` / `behavior` |
| `reason` | TEXT | ユーザー表示用の短い理由 |
| `last_event_at` | TEXT | 最終根拠イベント |
| `expires_at` | TEXT NULL | 行動由来メモリの減衰期限 |
| `created_at` | TEXT | 作成日時 |
| `updated_at` | TEXT | 更新日時 |

`(user_id, kind, value)` にUNIQUE制約を付ける。

### 4.8 `recommendation_feed_cache`

ユーザーごとの生成済みフィード。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `user_id` | TEXT FK | ユーザー |
| `feed_id` | TEXT | 同一生成単位 |
| `article_id` | TEXT FK | 記事 |
| `rank` | INTEGER | 順位 |
| `score` | REAL | 総合スコア |
| `reason_code` | TEXT | 推薦理由 |
| `reason_text_ja` | TEXT | 日本語理由 |
| `reason_text_en` | TEXT | 英語理由 |
| `generated_at` | TEXT | 生成日時 |
| `expires_at` | TEXT | 失効日時 |

主キーは `(user_id, feed_id, article_id)`。

### 4.9 年代別トレンド

初期ユーザー数が少ないため、最初から個人単位のトレンド画面は出さない。十分な利用者が集まった段階で `news_trends_daily` を追加する。

- 集計キー：日付、年代範囲、記事、ジャンル
- 保存値：表示人数、閲覧人数、保存人数、Cast化人数
- 最低20人以上のユニークユーザーがいる区分だけ表示する
- 管理画面にも個人別の年代閲覧履歴は表示しない

### 4.10 `daily_news_editions`

ユーザー別に確定した「今日の5件」とデイリーCastの状態を管理する。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `id` | TEXT PK | UUID |
| `user_id` | TEXT FK | ユーザー |
| `edition_date` | TEXT | `Asia/Tokyo`基準の日付 |
| `status` | TEXT | `building` / `ready` / `fallback` / `failed` |
| `cast_id` | TEXT NULL FK | 自動生成したCast |
| `auto_cast_status` | TEXT | `disabled` / `queued` / `processing` / `ready` / `skipped` / `failed` |
| `skip_reason` | TEXT NULL | 対象外理由 |
| `generated_at` | TEXT NULL | 5件の確定日時 |
| `created_at` | TEXT | 作成日時 |
| `updated_at` | TEXT | 更新日時 |

`(user_id, edition_date)` にUNIQUE制約を付け、バッチ再実行時の重複を防ぐ。

### 4.11 `daily_news_edition_items`

| カラム | 型 | 用途 |
| --- | --- | --- |
| `edition_id` | TEXT FK | 日次版 |
| `article_id` | TEXT FK | 選ばれた記事 |
| `rank` | INTEGER | 1〜5 |
| `score` | REAL | 選定スコア |
| `reason_code` | TEXT | 推薦理由コード |
| `reason_text_ja` | TEXT | 日本語理由 |
| `reason_text_en` | TEXT | 英語理由 |

主キーは `(edition_id, article_id)`、`(edition_id, rank)` にUNIQUE制約を付ける。

### 4.12 `news_article_ai_cache`

同じ記事をユーザーごとに再要約しないための共有キャッシュ。

| カラム | 型 | 用途 |
| --- | --- | --- |
| `article_id` | TEXT FK | 記事 |
| `language` | TEXT | `ja` / `en` |
| `content_hash` | TEXT | 本文更新検知 |
| `summary` | TEXT | 短い要約 |
| `script_segment` | TEXT | Castへ組み込める原稿断片 |
| `model` | TEXT | 生成モデル監査用 |
| `status` | TEXT | `ready` / `failed` |
| `created_at` | TEXT | 作成日時 |
| `expires_at` | TEXT | 再生成期限 |

主キーは `(article_id, language, content_hash)`。

### 4.13 `daily_cast_jobs`

| カラム | 型 | 用途 |
| --- | --- | --- |
| `id` | TEXT PK | UUID |
| `edition_id` | TEXT UNIQUE FK | 対象の日次版 |
| `user_id` | TEXT FK | ユーザー |
| `status` | TEXT | `queued` / `processing` / `retry_wait` / `completed` / `failed` |
| `stage` | TEXT | `fetch` / `summarize` / `script` / `audio` / `persist` |
| `attempt_count` | INTEGER | 試行回数 |
| `next_attempt_at` | TEXT NULL | 再試行時刻 |
| `lease_until` | TEXT NULL | Worker二重取得防止 |
| `error_code` | TEXT NULL | 失敗分類 |
| `created_at` | TEXT | 作成日時 |
| `updated_at` | TEXT | 更新日時 |

`edition_id`を一意にし、同じ日次版からCastが複数作られないようにする。

## 5. API設計

すべてBearer session認証を使用し、既存の `errorResponse` 形式へ合わせる。

### 5.1 Topics

`GET /api/recommendations/topics`

- 有効ジャンルを言語別に返す
- 認証前オンボーディングで必要なら公開専用endpointを別途用意する

### 5.2 Profile

`GET /api/recommendations/profile`

- 年代、任意性別、パーソナライズ可否、明示ジャンルを返す

`PUT /api/recommendations/profile`

- 初回設定または全体更新
- ジャンルは最低3件
- 年代・性別は未回答を許可する

`PATCH /api/recommendations/profile`

- パーソナライズ有効・無効、年代、ジャンルの部分更新

### 5.3 Feed

`GET /api/recommendations/feed?date=YYYY-MM-DD`

レスポンス：

```json
{
  "feedId": "uuid",
  "items": [
    {
      "article": {
        "id": "uuid",
        "url": "https://example.com/article",
        "title": "...",
        "description": "...",
        "imageURL": "https://...",
        "source": "example.com",
        "publishedAt": "2026-08-19T00:00:00Z"
      },
      "reason": "テクノロジーに興味があるため",
      "topicIDs": ["technology"]
    }
  ],
  "editionDate": "2026-08-19",
  "dailyCast": {
    "status": "ready",
    "castId": "uuid"
  },
  "generatedAt": "..."
}
```

- 当日の`daily_news_editions`に保存された5件を返す
- アプリの再読み込みではGDELTやAIを呼ばない
- 当日版が未生成なら共通キャッシュから同期的に5件を選ぶが、Cast生成は別Queueへ送る
- パーソナライズ無効時は汎用の新着・多様性から5件を返す
- 当日版が生成できず前日版を返す場合は`isFallback: true`を含める

### 5.4 Events

`POST /api/recommendations/events`

- 最大50件のイベントをまとめて受け付ける
- `id` のUNIQUE制約で再送を冪等にする
- `occurred_at` が未来すぎる、古すぎるイベントを拒否または補正する
- 保存後、強いイベントだけ同期的にメモリへ反映し、その他は遅延集計する

### 5.5 Memory

`GET /api/recommendations/memory`

- 明示ジャンル、学習したトピック・媒体、除外項目を返す

`PATCH /api/recommendations/memory/{id}`

- 重み、positive/negative、手動固定を変更する

`DELETE /api/recommendations/memory/{id}`

- 個別メモリを削除する

`DELETE /api/recommendations/memory`

- 行動由来メモリ、推薦イベント、フィードキャッシュを全削除する
- アカウント、課金、Cast、保存記事は削除しない

### 5.6 Provider更新

`POST /api/internal/news/refresh`

- Cron専用シークレットを検証する
- topic単位にGDELTを取得する
- canonical URLでupsertし、重複を排除する
- Provider障害を記録し、既存キャッシュを削除しない

### 5.7 日次版生成

`POST /api/internal/news/daily-editions`

- Cron専用シークレットを検証する
- `Asia/Tokyo`の対象日を明示して実行する
- 共通記事プールを更新後、対象ユーザーごとに5件を確定する
- 強い興味3件、関連ジャンル1件、探索枠1件を初期配分とする
- 既読、非表示、同一URL、同一内容を除外し、媒体とトピックの偏りを抑える
- `(user_id, edition_date)`のUNIQUE制約を使い、再実行を冪等にする
- 当日の候補不足時は前回キャッシュを利用し、最終的に前日版をfallbackとして返せる状態を残す

### 5.8 デイリーCast Queue

`POST /api/internal/daily-casts/enqueue`

- Plus／Pro、`daily_auto_cast_enabled = true`、AI同意済み、直近7日以内に利用、クレジットありのユーザーだけをenqueueする
- 対象外理由を`skip_reason`へ保存する
- クレジットを予約してから`daily_cast_jobs`を作成する
- 同じ`edition_id`のジョブが存在する場合は新規作成しない

`POST /api/internal/daily-casts/process`

- Queueから少数件ずつleaseして処理する
- 記事本文取得、共有要約、台本、Fish Audio、R2保存、Cast保存をstage単位で進める
- 完了済みstageを再実行せず、失敗したstageから指数バックオフで再試行する
- 成功時にクレジットを消費し、失敗確定時に予約を解放する
- 生成失敗によって日次ニュース5件を削除しない

## 6. GDELT連携

### 6.1 Providerインターフェース

`backend/lib/news/providers/provider.ts`

```ts
type NewsProvider = {
  search(input: NewsSearchInput): Promise<NewsCandidate[]>;
};
```

GDELT固有のフィールドをDBやiOSへ直接漏らさず、共通 `NewsCandidate` へ変換する。将来、別Providerを追加できるようにする。

### 6.2 取得戦略

- topicごとに英語クエリを定義する
- 日本語記事は言語・国フィルターと検索語展開を組み合わせる
- 初期MVPは毎日午前1時（`Asia/Tokyo`）に1回取得する
- 9ジャンルの場合、通常のGDELT検索は最大9クエリ/日を基本上限とする
- 同じtopicをユーザーごとに取得せず、全ユーザー共通の記事プールを作る
- ホーム更新やPull to RefreshではGDELTを呼ばず、Turso上の候補を再ランキングする
- GDELTからはジャンル別に候補をまとめてキャッシュし、ユーザーごとに5件だけを日次版へ保存する
- 日中に候補不足が発生してもユーザー操作からGDELTを直接呼ばず、共通キャッシュまたは前日版を使う
- GDELTレスポンスは短時間キャッシュし、タイムアウトと指数バックオフを設ける
- HTML本文はフィード表示時には取得せず、保存またはCast生成時だけ現在の本文取得処理を使う
- 自動Cast対象の記事だけAI要約し、記事・言語・本文hash単位で共有キャッシュする
- Embeddingは初期MVPでは生成しない

### 6.3 品質と安全性

- `http/https`以外を拒否する
- canonical URL、トラッキングパラメータ除去、content hashで重複排除する
- ドメインblocklistとallowlist補正を用意する
- タイトル欠落、公開日時不明、古すぎる記事を除外する
- 同じ媒体がフィードを占有しない上限を設ける
- 推薦しただけの記事にOpenAI/Fish Audioを使わない。Cast化時だけ既存のAI同意を適用する

## 7. 推薦アルゴリズム v1

機械学習モデルから始めず、説明可能な重み付きランキングから開始する。

### 7.1 初期スコア

```text
40% 明示ジャンル一致
25% 行動由来メモリ一致
15% 新しさ
10% 媒体品質
10% 多様性・探索
- 除外トピック／媒体ペナルティ
- 既読・重複ペナルティ
```

### 7.2 行動の初期重み

| イベント | 推奨加点 |
| --- | ---: |
| impression | 0 |
| open | +0.2 |
| 30秒以上の滞在 | +0.6 |
| save | +1.5 |
| add_to_cast | +2.0 |
| cast_completed | +2.5 |
| dislike | -3.0 |
| mute_topic | -5.0 |
| mute_source | -5.0 |

- 30日を基準に時間減衰させる
- 1回の誤タップで推薦が大きく変わらないようにする
- 明示的な「興味なし」は閲覧行動より強く扱う
- 新しいジャンルを10〜20%混ぜ、推薦が固定化しすぎないようにする

### 7.3 推薦理由

内部スコアをそのまま見せず、最も強い根拠を1件表示する。

- 「テクノロジーを選択しているため」
- 「最近、AIの記事を保存したため」
- 「よく読む媒体の新着です」
- 「同じ年代で注目されています」
- 「興味を広げる新しいトピックです」

## 8. iOS実装

### 8.1 新規モデル・Store

- `RecommendationModels.swift`
  - Topic、Profile、RecommendedArticle、FeedResponse、MemoryItem、RecommendationEvent
- `RecommendationClient.swift`
  - Topics、Profile、Feed、Events、Memory API
- `RecommendationStore.swift`
  - フィード、ページング、再読み込み、エラー、オフラインキャッシュ
- `MemoryStore.swift`
  - メモリ一覧、編集、削除、リセット
- `RecommendationEventQueue.swift`
  - 端末内キュー、バッチ送信、再送、重複防止

### 8.2 オンボーディング

- 既存オンボーディング後に任意のパーソナライズ設定を追加する
- 年代は範囲Picker
- 性別は任意で「回答しない」を初期選択にできる
- ジャンルは最低3件の複数選択
- スキップ時は汎用フィードを表示する
- 既存ユーザーには初回だけモーダルで案内し、後で設定可能にする

### 8.3 ホーム

- 現在のホームを `PersonalNewsHomeView` 中心へ再構成する
- 毎日の「今日の5件」を固定表示する
- 日付、更新時刻、デイリーCastの生成状態を表示できるようにする
- 記事カード、推薦理由、保存、興味なし、Cast候補追加を実装する
- Pull to Refreshは当日版をDBから再取得するだけにし、GDELTやAIを呼ばない
- 既存の期限間近記事・デトックス指標は下部へ移す
- 保存時は既存 `ArticleLibrary.addWithResult` を呼び、保存イベントも送る
- 記事閲覧は既存のアプリ内ブラウザを使い、開始・終了時刻から滞在イベントを作る
- デイリーCastが完成済みなら5件の上部または下部に1本の再生導線を表示する
- 生成中・対象外・失敗を区別し、ニュースカード自体は常に操作可能にする

### 8.4 アカウント

- 仮メニューを実際のNavigationLinkへ変更する
- プロフィールとプランの下に「興味ジャンル」をチップ形式で表示する
- ジャンルの「編集」から選択画面を開けるようにする
- 「メモリ」画面を追加する
- 明示ジャンル、学習トピック、よく読む媒体、表示を減らした項目を分ける
- 個別削除、「おすすめをリセット」、パーソナライズOFFを実装する
- ログは現在どおりアカウント内に維持する
- 設定は右上の歯車から開く構成を維持する

### 8.5 Cast連携

- 推薦記事の「Cast候補へ追加」はストックへ保存して選択候補にする
- Freeの手動Cast化は既存ストック画面へ送る
- Plus／Proは設定画面に「デイリーニュースCastを自動生成」を追加し、初回ON時にAI同意を確認する
- 自動Castは5件をまとめた1本としてCast一覧へ追加し、通常Castと同じプレイヤー・文字起こし・ダウンロードを利用する
- `add_to_cast`、`cast_created`、`cast_completed` を推薦イベントへ接続する
- URL手動入力とShare Extensionは変更せず残す

### 8.6 オフライン

- 最後に成功したフィードを端末へ保存する
- オフライン時はキャッシュ済み記事と保存記事を表示する
- オフライン中の行動イベントは端末キューへ追加し、復帰後に送信する

## 9. Backend実装構成

```text
backend/
  app/api/recommendations/
    topics/route.ts
    profile/route.ts
    feed/route.ts
    events/route.ts
    memory/route.ts
    memory/[id]/route.ts
  app/api/internal/news/refresh/route.ts
  app/api/internal/news/daily-editions/route.ts
  app/api/internal/daily-casts/enqueue/route.ts
  app/api/internal/daily-casts/process/route.ts
  lib/news/
    types.ts
    canonical-url.ts
    repository.ts
    refresh.ts
    providers/provider.ts
    providers/gdelt.ts
  lib/recommendations/
    profile.ts
    events.ts
    memory.ts
    ranker.ts
    feed.ts
    reasons.ts
    validation.ts
  lib/daily-news/
    edition-builder.ts
    eligibility.ts
    summary-cache.ts
    cast-queue.ts
    cast-worker.ts
    idempotency.ts
```

共通の認証処理は現行のBearer token検証を再利用する。API Routeごとに同じSQLを複製せず、認証済みuser ID取得を共通関数へ抽出する。

## 10. アカウント削除・保持期間

### 10.1 アカウント削除

既存 `DELETE /api/auth/account` に次の削除を追加する。

1. `recommendation_feed_cache`
2. `recommendation_events`
3. `user_memory_items`
4. `user_topic_preferences`
5. `user_recommendation_profiles`
6. `daily_cast_jobs`
7. `daily_news_edition_items`
8. `daily_news_editions`
9. 既存のCast、課金、プロフィール、認証データ
10. R2音声

共有記事キャッシュ `news_articles` はユーザー所有ではないため削除しない。

### 10.2 推奨保持期間

| データ | 推奨期間 |
| --- | --- |
| Feed cache | 24時間 |
| impression | 30日 |
| open / dwell | 90日 |
| save / dislike / mute | ユーザー削除またはメモリリセットまで |
| 行動由来memory | 最終イベントから180日で減衰・削除 |
| 共通記事候補 | 30日、参照中は延長 |
| 日次ニュース版 | 90日、ユーザー削除時は即時削除 |
| 記事要約キャッシュ | 30日または本文hash変更まで |
| 完了・失敗した生成ジョブ | 30日、監査に必要な最小情報のみ |
| 匿名トレンド集計 | 13か月 |

保持期間は実装前にプライバシーポリシーと合わせて確定する。

## 11. Admin実装

- Personal News Feature Flag
- GDELT最終成功時刻、失敗回数、取得記事数
- 24時間のProvider呼び出し回数と設定上限
- 日次版バッチの開始・完了時刻、対象人数、成功・fallback・失敗件数
- デイリーCast Queueの待機・処理中・再試行・失敗件数
- OpenAI要約キャッシュヒット率とFish Audio生成本数
- 管理者用の当日バッチ再実行・特定ユーザー再生成（冪等性を維持）
- topic別候補件数
- 記事ドメインblocklist
- 推薦イベント件数とエラー率の匿名集計
- メモリリセット件数
- 年代別トレンドの公開可否と最低人数
- テスター用「このユーザーの推薦を再生成」操作

通常管理者に個々の閲覧履歴本文を見せない。ユーザーサポートに必要な場合も、明示的権限と監査ログを必要とする。

## 12. Feature Flagと段階導入

| Flag | 用途 |
| --- | --- |
| `PERSONAL_NEWS_ENABLED` | 新ホーム全体 |
| `GDELT_PROVIDER_ENABLED` | GDELT取得 |
| `RECOMMENDATION_MEMORY_ENABLED` | 行動学習 |
| `AGE_TRENDS_ENABLED` | 年代別匿名トレンド |
| `DAILY_NEWS_EDITION_ENABLED` | 毎日のユーザー別5件 |
| `DAILY_CAST_ENABLED` | Plus／Pro向け自動デイリーCast |

### Rollout 1：内部基盤

- migration、Provider、記事キャッシュ、Topics API
- iOS画面は変更しない
- 管理画面で取得状況だけ確認する

### Rollout 2：明示ジャンルだけのフィード

- オンボーディング、Profile API、Home Feed
- アカウント画面へ選択ジャンルを表示
- 午前1時バッチでホームへ5件
- 行動学習なし
- 既存テスターだけに有効化する

### Rollout 3：メモリ学習

- Events、Memory、Ranker v1
- メモリ画面とリセット
- 推薦理由を表示する

### Rollout 4：Cast統合

- 保存、Cast候補、Cast完了イベントを接続する
- 自動生成設定、AI同意、対象判定、Queue Workerを追加する
- まずテスターだけに1日1本のデイリーCastを有効化する
- URL入力・Share Extensionとの共存を確認する

### Rollout 5：年代別トレンド

- 最低人数を満たした場合だけ有効化する
- 現在の少人数テスト期間ではOFFのままにする

## 13. テスト計画

### 13.1 DB・migration

- 空DBへ001〜新migrationを順番に適用できる
- 既存DBへ新migrationだけを適用して既存データが変わらない
- UNIQUE制約とindexが意図どおり動作する
- アカウント削除でユーザー別推薦データが残らない

### 13.2 Backend unit test

- URL canonicalization
- GDELTレスポンスのfixture変換
- 同一記事の重複排除
- 明示ジャンルだけのcold start順位
- 各イベントの重みと時間減衰
- dislike、muteの除外
- 媒体・ジャンル多様性
- 推薦理由の選択
- personalization OFF時の汎用フィード
- Event ID再送の冪等性
- 同じ日次バッチを複数回実行してもユーザー別5件とジョブが重複しない
- 5件が強い興味3・関連1・探索1の配分になる
- 自動Cast対象判定（プラン、設定、同意、最終利用、クレジット）
- 要約キャッシュの再利用と本文hash変更時の無効化
- Worker lease、stage再開、最大再試行、クレジット解放

### 13.3 Backend integration test

- 認証なしAPIは401
- 他ユーザーのProfile・Memoryを変更できない
- Profile更新後にFeedが変わる
- Event送信後にMemoryとFeedが変わる
- Provider障害時もキャッシュFeedを返す
- メモリ全削除後に初期推薦へ戻る
- GDELT障害時に共通キャッシュ、さらに前日版へfallbackする
- Plus／Pro対象者だけに日次ジョブが1件作られる
- Cast失敗時も当日の5件を返せる

### 13.4 iOS unit test

- API decoding
- `RecommendationStore`のloading、empty、error、offline状態
- イベントキューの永続化・バッチ送信・再送
- 保存記事連携
- パーソナライズOFF時の表示

### 13.5 iOS UI test

- 新規ユーザーがジャンルを3件選ぶ
- ホームに推薦記事が出る
- 記事を開き、戻るとイベントが送られる
- 保存した記事がストックへ出る
- 興味なしで記事が消える
- メモリを削除できる
- 推薦記事を保存し、既存フローでCast化できる
- Plus／Proで自動生成をONにし、完成したデイリーCastを再生できる
- Free、自動生成OFF、AI同意未完了では自動Castが作られない

### 13.6 プライバシー検証

- 性別未回答でも利用できる
- パーソナライズOFFでも汎用フィードを利用できる
- メモリ一覧が実際のランキング入力と一致する
- メモリ全削除後にイベント・キャッシュも削除される
- アカウント削除後にユーザー別データが0件になる
- 年代別集計が最低人数未満では返らない

## 14. 監視

初期リリースで最低限確認する指標：

- Provider取得成功率・応答時間
- Provider呼び出し回数/日
- 日次5件生成成功率・fallback率・完了時刻
- デイリーCast対象人数・生成成功率・平均完了時間
- OpenAI要約キャッシュヒット率
- 1ユーザー1日あたりのOpenAI・Fish Audio推定コスト
- 休眠除外とクレジット不足によるskip件数
- topic別候補件数
- Feed API成功率・P95応答時間
- empty feed率
- 記事open率、save率、dislike率、Cast候補追加率
- メモリリセット率、パーソナライズOFF率
- 推薦記事からCast作成までの転換率
- 既存のCast生成成功率

個人の閲覧内容をログ本文へ出さず、記事IDと集計値を中心に記録する。

## 15. 実装順序

### Phase 0：仕様確定

- 年代区分、ジャンル初期値、性別の扱いを確定
- 保持期間とApp Privacy申告を確定
- GDELT利用検証と代替Provider方針を決定
- Feature Flag方式を決定

### Phase 1：DBとBackend基盤

- `014_personal_news_core.sql`
- topic seed
- Profile、Topics API
- News Provider interfaceとGDELT adapter
- URL正規化・記事repository
- Internal refresh API
- 日次版、日次5件、要約キャッシュ、Cast Jobのmigration

### Phase 2：推薦API v1

- Feed、Events、Memory API
- 説明可能なranker
- Feed cache
- Provider障害時fallback
- Backend tests
- 午前1時の日次版Builderと冪等性

### Phase 3：iOSオンボーディングとホーム

- Model、Client、Store
- 年代・ジャンル選択
- Personal News Home
- アカウント画面の選択ジャンルチップ
- 記事閲覧、保存、興味なし
- オフラインFeed cache
- 「今日の5件」と日次Cast状態の表示

### Phase 4：メモリとアカウント

- Memory画面
- 個別編集・削除・全リセット
- パーソナライズON/OFF
- 仮メニューを実画面へ接続

### Phase 5：Cast連携

- Cast候補追加
- Cast生成・完了イベント
- 自動生成設定とAI同意
- 対象ユーザー判定、クレジット予約
- 共有要約キャッシュ、台本生成、Queue Worker
- 5件をまとめたデイリーCastの作成・再生
- 既存URL保存、Share Extension、課金制限の回帰確認

### Phase 6：Admin・削除・監視

- Provider health
- Feature Flag
- 推薦集計
- アカウント削除拡張
- データ保持cleanup

### Phase 7：年代別トレンド

- 匿名日次集計
- 最低人数制限
- UI追加
- 十分なユーザー数になるまでFlag OFF

## 16. 各Phaseの完了条件

| Phase | 完了条件 |
| --- | --- |
| 0 | 未決事項とプライバシー方針が文書化されている |
| 1 | DB migration適用、GDELT候補と日次版の保存先が作成される |
| 2 | 午前1時相当の実行でユーザー別5件が冪等に生成される |
| 3 | 実機でオンボーディングから「今日の5件」閲覧・記事保存まで完走する |
| 4 | メモリの確認・編集・全削除が実データへ反映される |
| 5 | 推薦記事から既存Cast生成に加え、対象ユーザーのデイリーCast生成・再生まで完走する |
| 6 | 削除、監視、Feature Flag、fallbackを確認できる |
| 7 | 匿名性テストに合格し、最低人数以上だけ表示される |

## 17. 主なリスクと対策

| リスク | 対策 |
| --- | --- |
| GDELTの品質・可用性 | Provider抽象化、共通キャッシュ、timeout、代替Provider |
| 日本語検索の精度 | 英語クエリ展開、言語・国filter、topic別手動調整 |
| フィルターバブル | 10〜20%の探索枠、媒体・topic多様性 |
| 誤タップで好みが変わる | openの重みを低くし、複数イベントで判断 |
| センシティブな推定 | 推定禁止カテゴリを定義し、明示ジャンル中心にする |
| DBイベント肥大化 | retention、batch、index、日次集計、cleanup |
| 午前1時の外部API集中 | 共通GDELT取得、Queue、同時実行上限、指数バックオフ |
| 自動Cast費用の増加 | 1日1本、5件まとめ、休眠除外、要約共有、クレジット上限、設定OFF |
| 日次バッチの二重実行 | UNIQUE制約、job lease、stage checkpoint、冪等キー |
| 日次Castだけ失敗 | ニュース5件と音声生成を分離し、5件は常に表示する |
| 既存Cast機能の回帰 | Feature Flag、段階導入、既存フローUIテスト |
| 少人数の年代別表示 | 最低20人、現在はFlag OFF |
| 推薦理由と実際の不一致 | reason codeをrankerと同時に生成する |

## 18. 実装開始前に決める項目

1. 年代区分は提案値でよいか
2. 性別を本当に取得するか。取得する場合も推薦v1では使用しない方針でよいか
3. 初期ジャンル9種でよいか
4. 推薦イベント保持期間を提案値でよいか
5. メモリをFreeを含む全プランへ提供するか
6. パーソナルニュース自体を無料にし、Cast生成量で課金する構成でよいか
7. GDELT以外の予備Providerを初期から用意するか
8. Feature Flagを環境変数、DB、管理画面のどこで管理するか
9. PlusのデイリーCastを5分固定、Proを長さ設定可とするか
10. 「直近7日以内に利用」を休眠除外条件としてよいか
11. デイリーCastが手動Castと同じ月間クレジットを消費する仕様でよいか
12. 午前1時に処理開始し、音声完成はQueue状況により順次となることを許容するか

## 19. 推奨する最初の着手範囲

最初からメモリ・年代トレンドまで同時に作らない。最初の縦切りは以下に限定する。

```text
3ジャンル選択
  → 午前1時に共通GDELT候補取得
  → 明示ジャンルだけでランキング
  → ユーザー別の「今日の5件」を保存
  → ホームへ5件表示
  → 開く／保存／興味なし
  → 保存記事を既存Castへ使用
```

この縦切りが実機で安定してから、イベント学習、メモリ画面、Plus／Pro向けデイリーCast、年代別トレンドを追加する。デイリーCastはさらに、対象判定 → Queue → 共有要約 → 1本の音声生成、の順でテスターへ段階導入する。

# StackCast Backend

## Authentication

認証データはTursoとこのバックエンドで管理します。Supabase／Firebaseは使用しません。

- メール: 6桁OTPを確認後、新規ユーザーだけ名前・パスワードを設定
- 登録済みメール: OTP確認後、そのままログイン
- Google: iOS公式SDKのIDトークンをGoogle公開鍵で検証し、プロフィール画像URLをDBへ保存
- Apple: AuthenticationServicesのIDトークンとnonceをApple公開鍵で検証
- セッション: 32バイトのランダムトークンを発行し、DBにはSHA-256ハッシュだけを保存

メールOTPは10分で失効し、最大5回まで入力できます。同じメールへの再送は60秒待機、送信回数はメール／IP単位で制限します。

## Local setup

```bash
cp .env.example .env.local
npm install
npm run db:migrate
npm run dev
```

開発環境で`RESEND_API_KEY`を設定していない場合、確認コードはバックエンドのターミナルにのみ表示されます。本番環境では`AUTH_OTP_SECRET`、`RESEND_API_KEY`、`AUTH_EMAIL_FROM`が必須です。

## Production configuration

### Email delivery

1. Resendで送信元ドメインを確認します。
2. `RESEND_API_KEY`をバックエンド環境変数に保存します。
3. `AUTH_EMAIL_FROM`を`StackCast <no-reply@auth.your-domain.com>`の形式で設定します。
4. `AUTH_OTP_SECRET`には十分に長いランダム値を設定します。アプリへは入れません。

### Google Sign-In

1. Google Cloud ConsoleでBundle ID `com.nexro.Tsundoku`のiOS OAuth Clientを作成します。
2. バックエンド認証用のWeb OAuth Clientも作成します。
3. iOS Client IDとWeb Client IDを`Tsundoku/Info.plist`へ設定します。
4. iOS Client IDの逆順URLスキームも`Tsundoku/Info.plist`へ設定します。
5. Web Client IDをバックエンドの`GOOGLE_SERVER_CLIENT_ID`へ設定します。

例: iOS Client IDが`123-example.apps.googleusercontent.com`の場合、URLスキームは`com.googleusercontent.apps.123-example`です。

### Sign in with Apple

1. Apple DeveloperのIdentifiersで`com.nexro.Tsundoku`にSign in with Appleを有効化します。
2. XcodeのSigning & Capabilitiesで同じTeamとBundle IDを使用します。
3. バックエンドの`APPLE_CLIENT_ID`に`com.nexro.Tsundoku`を設定します。

EntitlementとiOS側のnonce生成・送信処理は実装済みです。

## API

- `POST /api/auth/email/request-code`
- `POST /api/auth/email/verify-code`
- `POST /api/auth/email/complete`
- `POST /api/auth/google`
- `POST /api/auth/apple`
- `POST /api/auth/login`
- `GET /api/auth/me` with a Bearer token
- `POST /api/auth/logout` with a Bearer token
- `GET /api/health/db`

`GET /api/auth/me`は、ユーザーID・名前・メールアドレスに加えて、DBに保存された
`profileImageURL`を返します。Googleログイン時はGoogleアカウントの画像URLを保存・更新し、
Apple／メール登録で画像が提供されない場合は`null`になります。

旧`POST /api/auth/signup`はメール確認を迂回できないよう無効化されています。

## Backend URL selection

iOSアプリは`Tsundoku/Config.swift`の`Config.isProduction`で接続先を選択します。

- `false`: `http://localhost:3000`
- `true`: 本番URL

変更後はアプリを再ビルドして起動してください。

## Personal News / Daily Cast

`vercel.json` は5分間隔で `GET /api/internal/news/daily` を呼び出し、各ユーザーの保存タイムゾーンで15:45〜15:59を日次処理の実行・再試行枠として扱います。取得に成功した記事が直近6時間に5件以上あれば重複取得を抑止し、Providerが利用できない場合も30日間の共通キャッシュからfallback版を作ります。Vercel側には十分に長い `CRON_SECRET` を設定してください。候補ニュースはGDELTからジャンル単位で共通取得し、ユーザーごとの興味・閲覧メモリから5件のデイリー版を固定します。

主な環境変数:

- `CRON_SECRET`: cronエンドポイント認証用。必須
- `PERSONAL_NEWS_ENABLED`: `false` でPersonal News APIと日次処理を停止（既定 `true`）
- `DAILY_NEWS_EDITION_ENABLED`: `false` で日次候補取得・版生成を停止（既定 `true`）
- `GDELT_PROVIDER_ENABLED`: `false` でGDELT取得を停止（既定 `true`）
- `GDELT_REQUEST_TIMEOUT_MS`: GDELT 1リクエストの待ち時間（既定 `15000`、上限 `30000`）
- `GDELT_FAILURE_COOLDOWN_MS`: GDELT timeout/429 後に同一プロセスでGDELTをスキップする時間（既定15分）
- `GDELT_TIMESPAN`: GDELT検索窓（既定 `1d`）
- `OPENAI_NEWS_FALLBACK_ENABLED`: `false` でGDELT不足時のOpenAI Web Searchを停止（既定 `true`）
- `DEBUG_DAILY_NEWS_ENABLED`: 本番でデバッグ更新APIを明示的に有効化する場合のみ `true`（既定は本番無効）
- `RECOMMENDATION_MEMORY_ENABLED`: `false` で行動イベントからのメモリ学習を停止（既定 `true`）
- `DAILY_CAST_ENABLED`: `false` で自動Castのキュー投入・実行を停止（既定 `true`）
- `DAILY_CAST_INLINE_LIMIT`: 1回のcron内で処理する自動Cast数。`0...3`（既定 `3`）

自動Castは、Plus/Pro、アプリ内で自動作成を有効化済み、AI処理への同意済み、直近7日以内に利用したユーザーだけが対象です。日次エンドポイントを手動実行するとOpenAI/Fish Audioの実費処理が発生し得るため、本番環境での動作確認は対象アカウントを限定してください。

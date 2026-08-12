# StackCast Admin

StackCastのユーザー、オンボーディング、RevenueCat課金状態を管理する内部向けNext.jsアプリです。

## 環境変数

`admin/.env.local`に次を設定してください。

```dotenv
TURSO_DATABASE_URL=
TURSO_AUTH_TOKEN=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
ADMIN_BASE_URL=http://localhost:3000
ADMIN_ALLOWED_EMAILS=admin@example.com
ADMIN_PASSWORD=
ADMIN_SESSION_SECRET=
```

- `TURSO_*`は`backend/.env.local`と同じDBを指定します。
- `GOOGLE_CLIENT_ID`と`GOOGLE_CLIENT_SECRET`にはGoogle Cloud Consoleで作成したWebアプリケーション用OAuthクライアントの値を設定します。
- Google Cloud Consoleの承認済みリダイレクトURIには、ローカルで`http://localhost:3000/api/auth/google/callback`、本番で`https://<管理画面ドメイン>/api/auth/google/callback`を登録します。
- `ADMIN_BASE_URL`はリダイレクトURIのオリジンになる管理画面URLです。
- `ADMIN_ALLOWED_EMAILS`は管理画面を許可するGoogleアカウントをカンマ区切りで指定します。
- `ADMIN_PASSWORD`はGoogle認証後に入力する共通管理者パスワードです。
- `ADMIN_SESSION_SECRET`は32文字以上のランダムな値にしてください。

## DB

管理者プラン、オンボーディング管理情報、監査ログ、ログイン試行制限は、バックエンドの`007_admin_console.sql`で作成します。

```bash
cd ../backend
npm run db:migrate
```

## 起動

```bash
npm install
npm run dev
```

管理者が設定したプランはRevenueCatの購入履歴を上書きせず、`admin_plan_overrides`へ保存されます。サービス側の課金取得APIが有効なオーバーライドを優先し、iOSアプリにも反映します。すべての管理操作は`admin_audit_logs`へ記録されます。

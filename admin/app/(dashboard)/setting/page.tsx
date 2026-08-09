import type { Metadata } from "next";
import { Icon } from "@/components/icons";
import { Avatar, PageHeader, SectionCard } from "@/components/ui";
import { authenticationConfiguration, requireAdminSession } from "@/lib/auth";
import { getDatabaseStatus } from "@/lib/admin-data";

export const metadata: Metadata = { title: "設定" };

export default async function SettingPage() {
  const [admin, database] = await Promise.all([requireAdminSession(), getDatabaseStatus()]);
  const auth = authenticationConfiguration();

  return (
    <div className="page-container page-container-narrow">
      <PageHeader eyebrow="SETTING" title="管理設定" description="管理画面の接続・認証・セキュリティ状態を確認します。" />
      <SectionCard title="システム接続" description="機密値は表示されません">
        <div className="settings-list">
          <SettingRow icon="database" label="サービスDB" description={`${database.tableCount}テーブルを検出`} ready={database.connected} />
          <SettingRow icon="shield" label="Google認証" description="Google ID Tokenをサーバーで検証" ready={auth.google && auth.allowlist} />
          <SettingRow icon="shield" label="管理者パスワード" description="Google認証後に追加で要求" ready={auth.password} />
          <SettingRow icon="shield" label="セッション署名" description="HttpOnly・SameSite Cookie、12時間有効" ready={auth.sessionSecret} />
        </div>
      </SectionCard>

      <SectionCard title="現在の管理者" description="Google許可リストで認証済み">
        <div className="current-admin"><Avatar name={admin.name} imageURL={admin.picture} /><div><strong>{admin.name}</strong><span>{admin.email}</span></div><span className="badge badge-status-active">管理者</span></div>
      </SectionCard>

      <SectionCard title="必要な環境変数" description="admin/.env.local とデプロイ先に同じ値を設定">
        <div className="env-list">
          {[
            ["TURSO_DATABASE_URL", "サービス側と同じDB URL"],
            ["TURSO_AUTH_TOKEN", "サービス側と同じDBトークン"],
            ["GOOGLE_CLIENT_ID", "Google OAuth WebクライアントID"],
            ["GOOGLE_CLIENT_SECRET", "Google OAuth Webクライアントシークレット"],
            ["ADMIN_BASE_URL", "管理画面の公開URL（例: https://admin.example.com）"],
            ["ADMIN_ALLOWED_EMAILS", "許可するGoogleメール（カンマ区切り）"],
            ["ADMIN_PASSWORD", "2段階目の管理者パスワード"],
            ["ADMIN_SESSION_SECRET", "32文字以上のランダムな署名キー"],
          ].map(([name, description]) => <div className="env-row" key={name}><code>{name}</code><span>{description}</span></div>)}
        </div>
      </SectionCard>
    </div>
  );
}

function SettingRow({ icon, label, description, ready }: { icon: "database" | "shield"; label: string; description: string; ready: boolean }) {
  return <div className="setting-row"><div className="setting-icon"><Icon name={icon} className="h-5 w-5" /></div><div><strong>{label}</strong><span>{description}</span></div><span className={`config-state ${ready ? "config-ready" : "config-missing"}`}>{ready ? "設定済み" : "未設定"}</span></div>;
}

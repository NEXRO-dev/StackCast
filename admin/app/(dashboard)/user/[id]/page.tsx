import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Icon } from "@/components/icons";
import { OnboardingForm } from "@/components/onboarding-form";
import { PlanOverrideForm } from "@/components/plan-override-form";
import { Avatar, PageHeader, PlanBadge, SectionCard, StatusBadge } from "@/components/ui";
import { getUserDetail } from "@/lib/admin-data";
import { formatDateTime, onboardingLabel } from "@/lib/format";

export const metadata: Metadata = { title: "ユーザー詳細" };

export default async function UserDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const user = await getUserDetail(id);
  if (!user) notFound();

  return (
    <div className="page-container">
      <Link href="/user" className="back-link"><span>←</span>ユーザー一覧へ戻る</Link>
      <PageHeader
        eyebrow="USER DETAIL"
        title={user.name}
        description={user.email}
        action={<div className="header-badges"><PlanBadge plan={user.planTier} source={user.planSource} /><StatusBadge status={user.revenueCatStatus} active={Boolean(user.isActive)} /></div>}
      />

      <div className="user-profile-strip">
        <Avatar name={user.name} imageURL={user.profileImageURL} />
        <div><strong>{user.name}</strong><span>{user.email}</span></div>
        <dl>
          <div><dt>ユーザーID</dt><dd>{user.id}</dd></div>
          <div><dt>登録日</dt><dd>{formatDateTime(user.createdAt)}</dd></div>
          <div><dt>最終アクセス</dt><dd>{formatDateTime(user.lastSeenAt)}</dd></div>
          <div><dt>有効セッション</dt><dd>{user.sessionCount}</dd></div>
        </dl>
      </div>

      <div className="detail-grid">
        <div className="detail-main">
          <SectionCard title="課金プランの管理" description="管理者変更はRevenueCatの状態より優先されます">
            <div className="current-plan-panel">
              <div><span>現在の有効プラン</span><strong>{user.planTier.toUpperCase()}</strong></div>
              <div><span>決定元</span><strong>{user.planSource === "admin_override" ? "管理者オーバーライド" : user.planSource === "revenuecat" ? "RevenueCat" : "未契約"}</strong></div>
              <div><span>商品ID</span><strong className="mono-text">{user.productId ?? "—"}</strong></div>
              <div><span>期限</span><strong>{formatDateTime(user.overrideExpiresAt ?? user.revenueCatExpiresAt)}</strong></div>
            </div>
            <PlanOverrideForm userId={user.id} currentPlan={user.planTier} source={user.planSource} expiresAt={user.overrideExpiresAt} />
          </SectionCard>

          <SectionCard title="課金履歴" description="RevenueCat Webhookから保存されたレコード">
            {user.subscriptions.length ? <div className="table-scroll"><table className="data-table compact-table"><thead><tr><th>商品</th><th>プラン</th><th>環境</th><th>状態</th><th>購入日</th><th>期限</th></tr></thead><tbody>
              {user.subscriptions.map((subscription) => <tr key={subscription.id}><td className="mono-cell">{subscription.productId ?? "—"}</td><td><PlanBadge plan={subscription.planTier} /></td><td><span className={`environment-badge environment-${subscription.environment}`}>{subscription.environment}</span></td><td><StatusBadge status={subscription.status} active={Boolean(subscription.isActive)} /></td><td className="muted-cell">{formatDateTime(subscription.purchasedAt)}</td><td className="muted-cell">{formatDateTime(subscription.expiresAt)}</td></tr>)}
            </tbody></table></div> : <div className="empty-state">RevenueCatの課金履歴はありません。</div>}
          </SectionCard>

          <SectionCard title="オンボーディング管理" description={`現在: ${onboardingLabel(user.onboardingStatus)}`}>
            <OnboardingForm userId={user.id} initialStatus={user.onboardingStatus} initialNotes={user.onboardingNotes} />
          </SectionCard>
        </div>

        <aside className="detail-side">
          <SectionCard title="アカウント情報">
            <dl className="detail-list">
              <div><dt>メール</dt><dd>{user.email}</dd></div>
              <div><dt>認証方法</dt><dd>{user.identities.length ? user.identities.map((identity) => identity.provider).join(" / ") : "Email"}</dd></div>
              <div><dt>ストア</dt><dd>{user.store ?? "—"}</dd></div>
              <div><dt>環境</dt><dd>{user.environment ?? "—"}</dd></div>
              <div><dt>DB更新</dt><dd>{formatDateTime(user.updatedAt)}</dd></div>
            </dl>
          </SectionCard>

          <SectionCard title="監査ログ" description="直近20件">
            {user.auditLogs.length ? <div className="audit-list">{user.auditLogs.map((log) => <div className="audit-item" key={log.id}><span className="audit-icon"><Icon name="shield" className="h-4 w-4" /></span><div><strong>{auditLabel(log.action)}</strong><span>{log.adminEmail}</span><time>{formatDateTime(log.createdAt)}</time></div></div>)}</div> : <div className="empty-state empty-state-small">管理操作はまだありません。</div>}
          </SectionCard>
        </aside>
      </div>
    </div>
  );
}

function auditLabel(action: string) {
  const labels: Record<string, string> = {
    plan_override_set: "プランを変更",
    plan_override_cleared: "RevenueCatへ復帰",
    onboarding_updated: "オンボーディング更新",
  };
  return labels[action] ?? action;
}

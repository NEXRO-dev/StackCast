import type { Metadata } from "next";
import Link from "next/link";
import { Avatar, EmptyState, PageHeader, PlanBadge, StatCard, StatusBadge } from "@/components/ui";
import { getBillingData } from "@/lib/admin-data";
import { formatDateTime } from "@/lib/format";

export const metadata: Metadata = { title: "課金管理" };

export default async function BillingPage() {
  const data = await getBillingData();

  return (
    <div className="page-container">
      <PageHeader eyebrow="BILLING" title="課金管理" description="RevenueCatの課金状態と管理者オーバーライドを一元管理します。" />
      <div className="stat-grid stat-grid-four">
        <StatCard label="追跡中" value={data.trackedUsers} helper="課金履歴のあるユーザー" icon="billing" tone="blue" />
        <StatCard label="有効" value={data.activeUsers} helper="現在アクセス権あり" icon="check" tone="green" />
        <StatCard label="支払い問題" value={data.billingIssues} helper={`解約済み ${data.cancelledUsers}`} icon="alert" tone="red" />
        <StatCard label="管理者変更" value={data.overrides} helper="RevenueCatより優先" icon="shield" tone="violet" />
      </div>

      <section className="section-card table-card">
        <div className="section-card-header"><div><h2>サブスクリプション一覧</h2><p>最大200件を更新日時順に表示</p></div></div>
        {data.subscriptions.length ? (
          <div className="table-scroll"><table className="data-table"><thead><tr><th>ユーザー</th><th>有効プラン</th><th>商品</th><th>環境</th><th>状態</th><th>期限</th><th /></tr></thead><tbody>
            {data.subscriptions.map((item) => (
              <tr key={item.id}>
                <td><div className="user-cell"><Avatar name={item.name} imageURL={item.profileImageURL} /><div><strong>{item.name}</strong><span>{item.email}</span></div></div></td>
                <td><PlanBadge plan={item.planTier} source={item.planSource} /></td>
                <td className="mono-cell">{item.productId ?? "—"}</td>
                <td><span className={`environment-badge environment-${item.environment ?? "none"}`}>{item.environment ?? "—"}</span></td>
                <td><StatusBadge status={item.revenueCatStatus} active={Boolean(item.isActive)} /></td>
                <td className="muted-cell">{formatDateTime(item.overrideExpiresAt ?? item.revenueCatExpiresAt)}</td>
                <td><Link className="text-link" href={`/user/${item.id}`}>管理</Link></td>
              </tr>
            ))}
          </tbody></table></div>
        ) : <EmptyState>課金データはまだありません。</EmptyState>}
      </section>
    </div>
  );
}

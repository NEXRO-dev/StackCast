import type { Metadata } from "next";
import Link from "next/link";
import { Avatar, PageHeader, PlanBadge, SectionCard, StatCard, StatusBadge } from "@/components/ui";
import { getOverviewData, getPersonalNewsStats, getUserGrowthData } from "@/lib/admin-data";
import { UserGrowthChart } from "@/components/user-growth-chart";
import { formatDateTime } from "@/lib/format";

export const metadata: Metadata = { title: "概要" };

export default async function OverviewPage() {
  const data = await getOverviewData();
  const [growth, personalNews] = await Promise.all([getUserGrowthData(), getPersonalNewsStats()]);
  const completionRate = data.totalUsers
    ? Math.round((data.onboardingCompleted / data.totalUsers) * 100)
    : 0;

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="OVERVIEW"
        title="運用状況"
        description="ユーザー・課金・オンボーディングの現在地をまとめて確認できます。"
        action={<span className="live-indicator"><span />LIVE DATA</span>}
      />

      <div className="stat-grid stat-grid-four">
        <StatCard label="総ユーザー数" value={data.totalUsers.toLocaleString("ja-JP")} helper={`直近7日 +${data.newUsers7d}`} icon="users" tone="blue" />
        <StatCard label="有効な課金ユーザー" value={data.activePaidUsers.toLocaleString("ja-JP")} helper={`Plus ${data.plusUsers} · Pro ${data.proUsers}`} icon="billing" tone="green" />
        <StatCard label="オンボーディング完了" value={`${completionRate}%`} helper={`${data.onboardingCompleted} / ${data.totalUsers} ユーザー`} icon="onboarding" tone="violet" />
        <StatCard label="有効セッション" value={data.activeSessions.toLocaleString("ja-JP")} helper={`管理者変更 ${data.activeOverrides}件`} icon="trend" tone="amber" />
      </div>

      <div className="insight-strip">
        <div><span className="insight-dot insight-dot-production" /><strong>{data.productionPaidUsers}</strong><span>本番課金</span></div>
        <div><span className="insight-dot insight-dot-test" /><strong>{data.testPaidUsers}</strong><span>Sandbox課金</span></div>
        <div><span className="insight-dot insight-dot-override" /><strong>{data.activeOverrides}</strong><span>管理者オーバーライド</span></div>
        <p>課金状態はRevenueCat Webhookと管理者設定から統合しています。</p>
      </div>

      <UserGrowthChart sevenDays={growth.sevenDays} thirtyDays={growth.thirtyDays} />

      <SectionCard title="パーソナルニュース" description={`日次版 ${personalNews.editionDate ?? "未生成"}`}>
        <div className="stat-grid stat-grid-four">
          <StatCard label="記事候補プール" value={personalNews.articlePool} helper="期限内の共通候補" icon="onboarding" tone="blue" />
          <StatCard label="今日の5件" value={personalNews.readyEditions} helper={`Fallback ${personalNews.fallbackEditions} · 失敗 ${personalNews.failedEditions}`} icon="trend" tone="green" />
          <StatCard label="Cast生成待ち" value={personalNews.queuedCasts} helper={`処理中 ${personalNews.processingCasts}`} icon="billing" tone="amber" />
          <StatCard label="Cast生成完了" value={personalNews.completedCasts} helper={`失敗 ${personalNews.failedCasts}`} icon="dashboard" tone="violet" />
        </div>
      </SectionCard>

      <div className="dashboard-columns">
        <SectionCard title="最近登録したユーザー" description="新しいアカウント" href="/user">
          <div className="list-stack">
            {data.recentUsers.map((user) => (
              <Link className="activity-row" href={`/user/${user.id}`} key={user.id}>
                <Avatar name={user.name} imageURL={user.profileImageURL} />
                <div className="activity-primary"><strong>{user.name}</strong><span>{user.email}</span></div>
                <PlanBadge plan={user.planTier} source={user.planSource} />
                <time>{formatDateTime(user.createdAt)}</time>
              </Link>
            ))}
          </div>
        </SectionCard>

        <SectionCard title="最近の課金更新" description="Webhookで受信した変更" href="/billing">
          <div className="list-stack">
            {data.recentBilling.length ? data.recentBilling.map((item) => (
              <Link className="activity-row" href={`/user/${item.userId}`} key={item.id}>
                <Avatar name={item.name} imageURL={item.profileImageURL} />
                <div className="activity-primary"><strong>{item.name}</strong><span>{item.productId ?? "商品不明"} · {item.environment}</span></div>
                <StatusBadge status={item.status} />
                <time>{formatDateTime(item.updatedAt)}</time>
              </Link>
            )) : <div className="empty-state">課金更新はまだありません。</div>}
          </div>
        </SectionCard>
      </div>
    </div>
  );
}

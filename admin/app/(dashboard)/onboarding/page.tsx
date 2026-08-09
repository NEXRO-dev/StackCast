import type { Metadata } from "next";
import Link from "next/link";
import { Avatar, PageHeader, PlanBadge, StatCard } from "@/components/ui";
import { getOnboardingData } from "@/lib/admin-data";
import { formatDateTime, onboardingLabel } from "@/lib/format";

export const metadata: Metadata = { title: "オンボーディング" };

export default async function OnboardingPage() {
  const data = await getOnboardingData();
  const completedRate = data.total ? Math.round((data.completed / data.total) * 100) : 0;

  return (
    <div className="page-container">
      <PageHeader eyebrow="ONBOARDING" title="オンボーディング" description="登録後のセットアップ進捗と認証状況を追跡します。" />
      <div className="stat-grid stat-grid-four">
        <StatCard label="完了" value={data.completed} helper={`${completedRate}% のユーザー`} icon="check" tone="green" />
        <StatCard label="進行中" value={data.inProgress} helper="セットアップ途中" icon="clock" tone="amber" />
        <StatCard label="未開始" value={data.notStarted} helper="フォロー対象" icon="alert" tone="red" />
        <StatCard label="Google連携" value={data.googleUsers} helper={`${data.total}人中`} icon="shield" tone="blue" />
      </div>

      <section className="section-card onboarding-summary">
        <div className="section-card-header"><div><h2>全体進捗</h2><p>管理ステータスとサービス利用状況から集計</p></div><strong>{completedRate}%</strong></div>
        <div className="progress-track"><span style={{ width: `${completedRate}%` }} /></div>
        <div className="progress-legend"><span><i className="legend-complete" />完了 {data.completed}</span><span><i className="legend-progress" />進行中 {data.inProgress}</span><span><i className="legend-empty" />未開始 {data.notStarted}</span></div>
      </section>

      <section className="section-card table-card">
        <div className="section-card-header"><div><h2>ユーザー別進捗</h2><p>詳細画面からステータスと管理メモを更新できます</p></div></div>
        <div className="table-scroll"><table className="data-table"><thead><tr><th>ユーザー</th><th>ステータス</th><th>認証</th><th>プロフィール</th><th>プラン</th><th>登録日</th><th /></tr></thead><tbody>
          {data.users.map((user) => (
            <tr key={user.id}>
              <td><div className="user-cell"><Avatar name={user.name} imageURL={user.profileImageURL} /><div><strong>{user.name}</strong><span>{user.email}</span></div></div></td>
              <td><span className={`badge onboarding-${user.onboardingStatus}`}>{onboardingLabel(user.onboardingStatus)}</span></td>
              <td className="muted-cell">{user.hasGoogle ? "Google" : user.hasApple ? "Apple" : "Email"}</td>
              <td className="muted-cell">{user.hasProfile ? "設定済み" : "未設定"}</td>
              <td><PlanBadge plan={user.planTier} /></td>
              <td className="muted-cell">{formatDateTime(user.createdAt)}</td>
              <td><Link className="text-link" href={`/user/${user.id}`}>確認</Link></td>
            </tr>
          ))}
        </tbody></table></div>
      </section>
    </div>
  );
}

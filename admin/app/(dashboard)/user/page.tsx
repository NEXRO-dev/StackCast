import type { Metadata } from "next";
import Link from "next/link";
import { Icon } from "@/components/icons";
import { Avatar, EmptyState, PageHeader, PlanBadge, StatusBadge } from "@/components/ui";
import { getUsers } from "@/lib/admin-data";
import { formatDateTime } from "@/lib/format";

export const metadata: Metadata = { title: "ユーザー" };

export default async function UsersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; plan?: string; page?: string }>;
}) {
  const params = await searchParams;
  const data = await getUsers({
    query: params.q,
    plan: params.plan,
    page: Number(params.page) || 1,
  });

  return (
    <div className="page-container">
      <PageHeader eyebrow="USER" title="ユーザー管理" description="登録ユーザー、ログイン状況、現在の課金プランを確認します。" />

      <section className="section-card table-card">
        <form className="table-toolbar" method="get">
          <label className="search-field">
            <Icon name="search" className="h-5 w-5" />
            <input name="q" defaultValue={data.query} placeholder="名前・メール・ユーザーIDで検索" />
          </label>
          <select name="plan" defaultValue={data.plan} aria-label="プランで絞り込み">
            <option value="all">すべてのプラン</option>
            <option value="free">Free</option>
            <option value="plus">Plus</option>
            <option value="pro">Pro</option>
          </select>
          <button className="secondary-button" type="submit">絞り込む</button>
          <span className="result-count">{data.total.toLocaleString("ja-JP")} users</span>
        </form>

        {data.users.length ? (
          <div className="table-scroll">
            <table className="data-table">
              <thead><tr><th>ユーザー</th><th>プラン</th><th>課金状態</th><th>最終アクセス</th><th>登録日</th><th /></tr></thead>
              <tbody>
                {data.users.map((user) => (
                  <tr key={user.id}>
                    <td><div className="user-cell"><Avatar name={user.name} imageURL={user.profileImageURL} /><div><strong>{user.name}</strong><span>{user.email}</span><small>{user.id}</small></div></div></td>
                    <td><PlanBadge plan={user.planTier} source={user.planSource} /></td>
                    <td><StatusBadge status={user.revenueCatStatus} active={Boolean(user.isActive)} /></td>
                    <td className="muted-cell">{formatDateTime(user.lastSeenAt)}</td>
                    <td className="muted-cell">{formatDateTime(user.createdAt)}</td>
                    <td><Link className="row-action" href={`/user/${user.id}`} aria-label={`${user.name}の詳細`}><Icon name="arrow" className="h-4 w-4" /></Link></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : <EmptyState>条件に一致するユーザーはいません。</EmptyState>}

        <div className="pagination">
          <PaginationLink disabled={data.page <= 1} page={data.page - 1} query={data.query} plan={data.plan}>前へ</PaginationLink>
          <span>{data.page} / {data.totalPages}</span>
          <PaginationLink disabled={data.page >= data.totalPages} page={data.page + 1} query={data.query} plan={data.plan}>次へ</PaginationLink>
        </div>
      </section>
    </div>
  );
}

function PaginationLink({ disabled, page, query, plan, children }: { disabled: boolean; page: number; query: string; plan: string; children: React.ReactNode }) {
  if (disabled) return <span className="pagination-link pagination-link-disabled">{children}</span>;
  const params = new URLSearchParams({ page: String(page), plan });
  if (query) params.set("q", query);
  return <Link className="pagination-link" href={`/user?${params.toString()}`}>{children}</Link>;
}

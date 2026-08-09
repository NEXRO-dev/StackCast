import Link from "next/link";
import { Icon, type IconName } from "@/components/icons";
export { Avatar } from "@/components/avatar";

export function PageHeader({
  eyebrow,
  title,
  description,
  action,
}: {
  eyebrow: string;
  title: string;
  description: string;
  action?: React.ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        <p className="page-eyebrow">{eyebrow}</p>
        <h1 className="page-title">{title}</h1>
        <p className="page-description">{description}</p>
      </div>
      {action ? <div className="page-action">{action}</div> : null}
    </header>
  );
}

export function StatCard({
  label,
  value,
  helper,
  icon,
  tone = "blue",
}: {
  label: string;
  value: string | number;
  helper: string;
  icon: IconName;
  tone?: "blue" | "green" | "amber" | "violet" | "red";
}) {
  return (
    <article className="stat-card">
      <div className={`stat-icon stat-icon-${tone}`}>
        <Icon name={icon} className="h-5 w-5" />
      </div>
      <div className="stat-copy">
        <p className="stat-label">{label}</p>
        <p className="stat-value">{value}</p>
        <p className="stat-helper">{helper}</p>
      </div>
    </article>
  );
}

export function SectionCard({
  title,
  description,
  href,
  children,
  className = "",
}: {
  title: string;
  description?: string;
  href?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={`section-card ${className}`}>
      <div className="section-card-header">
        <div>
          <h2>{title}</h2>
          {description ? <p>{description}</p> : null}
        </div>
        {href ? (
          <Link href={href} className="text-link">
            すべて見る
            <Icon name="arrow" className="h-4 w-4" />
          </Link>
        ) : null}
      </div>
      {children}
    </section>
  );
}

export function PlanBadge({ plan, source }: { plan: string | null; source?: string }) {
  const normalized = plan?.toLowerCase() ?? "free";
  return (
    <span className={`badge badge-plan badge-${normalized}`}>
      {normalized === "plus"
        ? "Plus"
        : normalized === "pro"
          ? "Pro"
          : normalized === "lifetime"
            ? "Lifetime"
            : "Free"}
      {source === "admin_override" ? <span className="override-mark">管理</span> : null}
    </span>
  );
}

export function StatusBadge({ status, active }: { status?: string | null; active?: boolean }) {
  const value = status ?? (active ? "active" : "none");
  const label: Record<string, string> = {
    active: "有効",
    expired: "期限切れ",
    cancelled: "解約済み",
    billing_issue: "支払い問題",
    paused: "停止中",
    none: "未契約",
  };
  return <span className={`badge badge-status badge-status-${value}`}>{label[value] ?? value}</span>;
}

export function EmptyState({ children }: { children: React.ReactNode }) {
  return <div className="empty-state">{children}</div>;
}

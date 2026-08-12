"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icon, type IconName } from "@/components/icons";
import { Avatar } from "@/components/avatar";
import type { AdminIdentity } from "@/lib/auth";

const navigation: Array<{ href: string; label: string; icon: IconName }> = [
  { href: "/overview", label: "概要", icon: "dashboard" },
  { href: "/user", label: "ユーザー", icon: "users" },
  { href: "/billing", label: "課金管理", icon: "billing" },
  { href: "/onboarding", label: "オンボーディング", icon: "onboarding" },
  { href: "/setting", label: "設定", icon: "settings" },
];

export function Sidebar({
  admin,
  collapsed,
  onToggle,
}: {
  admin: AdminIdentity;
  collapsed: boolean;
  onToggle: () => void;
}) {
  const pathname = usePathname();

  return (
    <aside className="admin-sidebar" aria-label="管理画面サイドバー">
      <div className="sidebar-brand">
        <div className="brand-mark">S</div>
        <div className="sidebar-brand-copy">
          <p className="brand-name">StackCast</p>
          <p className="brand-caption">ADMIN CONSOLE</p>
        </div>
        <button className="sidebar-toggle" type="button" onClick={onToggle} aria-label={collapsed ? "サイドバーを展開" : "サイドバーを折りたたむ"} aria-expanded={!collapsed}>
          <Icon name={collapsed ? "chevron-right" : "chevron-left"} className="h-4 w-4" />
        </button>
      </div>

      <nav className="sidebar-nav" aria-label="管理画面ナビゲーション">
        <p className="sidebar-section-label">MANAGEMENT</p>
        {navigation.map((item) => {
          const active =
            pathname === item.href ||
            (item.href !== "/overview" && pathname.startsWith(`${item.href}/`));
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`sidebar-link sidebar-link-${item.icon} ${active ? "sidebar-link-active" : ""}`}
              title={collapsed ? item.label : undefined}
            >
              <Icon name={item.icon} className="h-5 w-5" />
              <span className="sidebar-link-label">{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="sidebar-footer">
        <div className="sidebar-account">
          <Avatar name={admin.name} imageURL={admin.picture} className="sidebar-avatar" />
          <div className="sidebar-account-copy">
            <strong>{admin.name}</strong>
            <p className="admin-email" title={admin.email}>{admin.email}</p>
          </div>
        </div>
        <form action="/api/auth/logout" method="post">
          <button className="logout-button" type="submit" title="ログアウト">
            <Icon name="logout" className="h-4 w-4" />
            <span className="sidebar-link-label">ログアウト</span>
          </button>
        </form>
      </div>
    </aside>
  );
}

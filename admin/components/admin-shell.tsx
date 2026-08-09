"use client";

import { useState } from "react";
import { Sidebar } from "@/components/sidebar";
import type { AdminIdentity } from "@/lib/auth";

export function AdminShell({ admin, children }: { admin: AdminIdentity; children: React.ReactNode }) {
  const [collapsed, setCollapsed] = useState(false);

  return (
    <div className={`admin-shell ${collapsed ? "admin-shell-collapsed" : ""}`}>
      <Sidebar admin={admin} collapsed={collapsed} onToggle={() => setCollapsed((value) => !value)} />
      <main className="admin-main">{children}</main>
    </div>
  );
}

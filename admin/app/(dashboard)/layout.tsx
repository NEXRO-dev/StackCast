import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

export default async function DashboardLayout({ children }: LayoutProps<"/">) {
  const admin = await requireAdminSession();

  return <AdminShell admin={admin}>{children}</AdminShell>;
}

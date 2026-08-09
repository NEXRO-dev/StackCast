import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { LoginForm } from "@/components/login-form";
import { getAdminSession, getPendingAdmin } from "@/lib/auth";

export const metadata: Metadata = { title: "ログイン" };
export const dynamic = "force-dynamic";

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ error?: string }>;
}) {
  if (await getAdminSession()) redirect("/overview");
  const pendingIdentity = await getPendingAdmin();
  const error = errorMessage((await searchParams).error);

  return (
    <main className="login-shell">
      <div className="login-backdrop login-backdrop-one" />
      <div className="login-backdrop login-backdrop-two" />
      <LoginForm initialIdentity={pendingIdentity} initialError={error} />
      <p className="login-footer">StashCast Internal Management · Authorized personnel only</p>
    </main>
  );
}

function errorMessage(code: string | undefined) {
  switch (code) {
    case "configuration":
      return "Google OAuthの設定が不足しています。環境変数を確認してください。";
    case "google_cancelled":
      return "Google認証がキャンセルされました。";
    case "google_failed":
      return "Googleアカウントを確認できませんでした。許可リストとOAuth設定を確認してください。";
    default:
      return null;
  }
}

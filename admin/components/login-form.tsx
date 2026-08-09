"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { AdminIdentity } from "@/lib/auth";
import { Icon } from "@/components/icons";

export function LoginForm({
  initialIdentity,
  initialError,
}: {
  initialIdentity: AdminIdentity | null;
  initialError: string | null;
}) {
  const router = useRouter();
  const [identity, setIdentity] = useState(initialIdentity);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(initialError);

  async function submitPassword(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const password = new FormData(form).get("password");
    setLoading(true);
    setError(null);

    try {
      const result = await fetch("/api/auth/password", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password }),
      });
      const body = (await result.json()) as { error?: string };
      if (!result.ok) throw new Error(body.error || "認証に失敗しました。");
      router.push("/overview");
      router.refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "認証に失敗しました。");
      form.reset();
    } finally {
      setLoading(false);
    }
  }

  async function resetGoogleAccount() {
    setLoading(true);
    await fetch("/api/auth/reset", { method: "POST" });
    setIdentity(null);
    setError(null);
    setLoading(false);
  }

  return (
    <div className="login-card">
      <div className="login-icon"><Icon name="shield" className="h-7 w-7" /></div>
      <p className="login-kicker">STASHCAST ADMIN</p>
      <h1>管理画面にログイン</h1>
      <p className="login-description">
        Googleアカウントと管理者パスワードの2段階で認証します。
      </p>

      {!identity ? (
        <div className="google-stage">
          <div className="auth-step-row">
            <span className="auth-step auth-step-active">1</span>
            <span className="auth-step-line" />
            <span className="auth-step">2</span>
          </div>
          <a className="google-oauth-button" href="/api/auth/google/start">
            <svg viewBox="0 0 24 24" aria-hidden="true">
              <path fill="#4285F4" d="M21.6 12.23c0-.71-.06-1.4-.18-2.07H12v3.91h5.38a4.6 4.6 0 0 1-2 3.02v2.54h3.24c1.9-1.75 2.98-4.33 2.98-7.4Z" />
              <path fill="#34A853" d="M12 22c2.7 0 4.98-.9 6.63-2.43l-3.24-2.54c-.9.6-2.05.96-3.39.96-2.61 0-4.83-1.77-5.62-4.14H3.04v2.62A10 10 0 0 0 12 22Z" />
              <path fill="#FBBC05" d="M6.38 13.85A6 6 0 0 1 6.07 12c0-.64.11-1.27.31-1.85V7.53H3.04A10 10 0 0 0 2 12c0 1.61.39 3.14 1.04 4.47l3.34-2.62Z" />
              <path fill="#EA4335" d="M12 6.01c1.47 0 2.79.5 3.83 1.5l2.87-2.87A9.65 9.65 0 0 0 12 2a10 10 0 0 0-8.96 5.53l3.34 2.62C7.17 7.78 9.39 6.01 12 6.01Z" />
            </svg>
            Googleで続ける
          </a>
        </div>
      ) : (
        <form className="password-stage" onSubmit={submitPassword}>
          <div className="auth-step-row">
            <span className="auth-step auth-step-complete"><Icon name="check" className="h-4 w-4" /></span>
            <span className="auth-step-line auth-step-line-complete" />
            <span className="auth-step auth-step-active">2</span>
          </div>
          <div className="verified-account">
            <span className="avatar avatar-large">{identity.name.slice(0, 1)}</span>
            <div>
              <strong>{identity.name}</strong>
              <span>{identity.email}</span>
            </div>
            <button type="button" onClick={resetGoogleAccount} disabled={loading}>変更</button>
          </div>
          <label className="field-label" htmlFor="admin-password">管理者パスワード</label>
          <input
            id="admin-password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            autoFocus
            className="text-input"
            placeholder="パスワードを入力"
          />
          <button className="primary-button" type="submit" disabled={loading}>
            {loading ? "確認中…" : "管理画面を開く"}
          </button>
        </form>
      )}

      {error ? <p className="form-error" role="alert">{error}</p> : null}
      <p className="security-note"><Icon name="shield" className="h-4 w-4" />認証情報はサーバー側で検証されます</p>
    </div>
  );
}

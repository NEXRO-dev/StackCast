"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function PlanOverrideForm({
  userId,
  currentPlan,
  source,
  expiresAt,
}: {
  userId: string;
  currentPlan: string;
  source: string;
  expiresAt: string | null;
}) {
  const router = useRouter();
  const [plan, setPlan] = useState(source === "admin_override" ? currentPlan : "revenuecat");
  const [reason, setReason] = useState("");
  const [expiration, setExpiration] = useState(toLocalDateTime(expiresAt));
  const [loading, setLoading] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setMessage(null);
    setError(null);

    try {
      const response = await fetch(`/api/admin/users/${encodeURIComponent(userId)}/plan`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          planTier: plan,
          reason,
          expiresAt: expiration ? new Date(expiration).toISOString() : null,
        }),
      });
      const body = (await response.json()) as { error?: string };
      if (!response.ok) throw new Error(body.error || "プランを更新できませんでした。");
      setMessage(plan === "revenuecat" ? "RevenueCatの状態に戻しました。" : "管理者プランを保存しました。");
      setReason("");
      setConfirmed(false);
      router.refresh();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "プランを更新できませんでした。");
    } finally {
      setLoading(false);
    }
  }

  return (
    <form className="control-form" onSubmit={submit}>
      <div className="form-grid">
        <label>
          <span>適用するプラン</span>
          <select value={plan} onChange={(event) => setPlan(event.target.value)}>
            <option value="revenuecat">RevenueCatに従う</option>
            <option value="free">Freeへ変更</option>
            <option value="plus">Plusを付与</option>
            <option value="pro">Proを付与</option>
          </select>
        </label>
        <label>
          <span>有効期限（任意）</span>
          <input
            type="datetime-local"
            value={expiration}
            onChange={(event) => setExpiration(event.target.value)}
            disabled={plan === "revenuecat"}
          />
        </label>
      </div>
      <label>
        <span>変更理由</span>
        <input
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          placeholder="例：カスタマーサポート対応"
          minLength={3}
          required
        />
      </label>
      <div className="form-footer">
        <label className="confirmation-check">
          <input type="checkbox" checked={confirmed} onChange={(event) => setConfirmed(event.target.checked)} />
          <span>変更内容とユーザーへの影響を確認しました</span>
        </label>
        <button className="primary-button primary-button-compact" disabled={loading || !confirmed} type="submit">
          {loading ? "保存中…" : "プランを保存"}
        </button>
      </div>
      <p className="audit-note">変更者・理由・日時は監査ログへ保存されます。</p>
      {message ? <p className="form-success">{message}</p> : null}
      {error ? <p className="form-error">{error}</p> : null}
    </form>
  );
}

function toLocalDateTime(value: string | null) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

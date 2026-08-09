"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";

export function OnboardingForm({
  userId,
  initialStatus,
  initialNotes,
}: {
  userId: string;
  initialStatus: string;
  initialNotes: string | null;
}) {
  const router = useRouter();
  const [status, setStatus] = useState(initialStatus);
  const [notes, setNotes] = useState(initialNotes ?? "");
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setMessage(null);
    const response = await fetch(`/api/admin/users/${encodeURIComponent(userId)}/onboarding`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ status, notes }),
    });
    setLoading(false);
    setMessage(response.ok ? "オンボーディング情報を保存しました。" : "保存に失敗しました。");
    if (response.ok) router.refresh();
  }

  return (
    <form className="control-form" onSubmit={submit}>
      <div className="form-grid">
        <label>
          <span>ステータス</span>
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="not_started">未開始</option>
            <option value="in_progress">進行中</option>
            <option value="completed">完了</option>
          </select>
        </label>
      </div>
      <label>
        <span>管理メモ</span>
        <textarea
          value={notes}
          onChange={(event) => setNotes(event.target.value)}
          placeholder="サポート状況や確認事項を記録"
          maxLength={2000}
        />
      </label>
      <div className="form-footer">
        <p>このメモは管理画面でのみ表示されます。</p>
        <button className="secondary-button" type="submit" disabled={loading}>
          {loading ? "保存中…" : "保存"}
        </button>
      </div>
      {message ? <p className={responseClass(message)}>{message}</p> : null}
    </form>
  );
}

function responseClass(message: string) {
  return message.includes("失敗") ? "form-error" : "form-success";
}

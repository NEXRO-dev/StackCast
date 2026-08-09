const dateTimeFormatter = new Intl.DateTimeFormat("ja-JP", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
});

const dateFormatter = new Intl.DateTimeFormat("ja-JP", {
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

export function formatDateTime(value: string | null | undefined) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : dateTimeFormatter.format(date);
}

export function formatDate(value: string | null | undefined) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "—" : dateFormatter.format(date);
}

export function planLabel(plan: string | null | undefined) {
  switch (plan?.toLowerCase()) {
    case "plus":
      return "Plus";
    case "pro":
      return "Pro";
    case "lifetime":
      return "Lifetime";
    default:
      return "Free";
  }
}

export function statusLabel(status: string | null | undefined) {
  switch (status) {
    case "active":
      return "有効";
    case "expired":
      return "期限切れ";
    case "cancelled":
      return "解約済み";
    case "billing_issue":
      return "支払い問題";
    case "paused":
      return "停止中";
    default:
      return "未契約";
  }
}

export function onboardingLabel(status: string) {
  switch (status) {
    case "completed":
      return "完了";
    case "in_progress":
      return "進行中";
    default:
      return "未開始";
  }
}

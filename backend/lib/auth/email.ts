type VerificationEmail = {
  to: string;
  code: string;
  idempotencyKey: string;
};

export async function sendVerificationEmail({
  to,
  code,
  idempotencyKey,
}: VerificationEmail): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY?.trim();

  if (!apiKey) {
    if (process.env.NODE_ENV === "production") {
      throw new Error("Missing required environment variable: RESEND_API_KEY");
    }

    console.info(`[development email] ${to}: verification code ${code}`);
    return;
  }

  const from = requiredEnvironmentVariable("AUTH_EMAIL_FROM");
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
      "Idempotency-Key": idempotencyKey,
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject: "StackCastの確認コード",
      text: [
        "StackCastのメールアドレス確認コードです。",
        "",
        code,
        "",
        "このコードは10分間有効です。心当たりがない場合は、このメールを無視してください。",
      ].join("\n"),
      html: `<p>StackCastのメールアドレス確認コードです。</p><p style="font-size:32px;font-weight:700;letter-spacing:8px">${code}</p><p>このコードは10分間有効です。心当たりがない場合は、このメールを無視してください。</p>`,
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Resend delivery failed (${response.status}): ${body}`);
  }
}

function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();

  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }

  return value;
}

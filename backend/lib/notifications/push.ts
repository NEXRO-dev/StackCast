import { SignJWT, importPKCS8 } from "jose";
import { getTurso } from "@/lib/turso";

type PushEnvironment = "sandbox" | "production";

type PushTokenRow = { token: string; environment: PushEnvironment };

function configuration() {
  const key = process.env.APNS_AUTH_KEY_P8?.trim();
  const keyID = process.env.APNS_KEY_ID?.trim();
  const teamID = process.env.APNS_TEAM_ID?.trim();
  const bundleID = process.env.APNS_BUNDLE_ID?.trim() || "com.nexro.Tsundoku";
  if (!key || !keyID || !teamID) return null;
  return { key: key.replace(/\\n/g, "\n"), keyID, teamID, bundleID };
}

async function apnsJWT(config: NonNullable<ReturnType<typeof configuration>>) {
  const privateKey = await importPKCS8(config.key, "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyID })
    .setIssuer(config.teamID)
    .setIssuedAt()
    .setExpirationTime("55m")
    .sign(privateKey);
}

export async function sendUserPush(
  userID: string,
  input: { title: string; body: string; deepLink?: string },
) {
  const config = configuration();
  if (!config) {
    console.info("[push] APNs is not configured; notification skipped", { userID });
    return { sent: 0, skipped: "not_configured" };
  }

  const rows = (await getTurso().all(
    "SELECT token, environment FROM push_device_tokens WHERE user_id = ?",
    userID,
  )) as PushTokenRow[];
  if (rows.length === 0) return { sent: 0, skipped: "no_devices" };

  const token = await apnsJWT(config);
  let sent = 0;
  for (const row of rows) {
    const host = row.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${row.token}`, {
      method: "POST",
      signal: AbortSignal.timeout(10_000),
      headers: {
        authorization: `bearer ${token}`,
        "apns-topic": config.bundleID,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: { alert: { title: input.title, body: input.body }, sound: "default" },
        deepLink: input.deepLink ?? "",
      }),
    });
    if (response.ok) {
      sent += 1;
    } else {
      const details = await response.text().catch(() => "");
      console.warn("[push] APNs request failed", { userID, status: response.status, details });
      if (response.status === 400 || response.status === 410) {
        await getTurso().run("DELETE FROM push_device_tokens WHERE token = ?", row.token);
      }
    }
  }
  return { sent };
}

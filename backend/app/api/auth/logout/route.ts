import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const token = bearerToken(request);

  if (token) {
    await getTurso().run(
      "DELETE FROM auth_sessions WHERE token_hash = ?",
      hashSessionToken(token),
    );
  }

  return new Response(null, { status: 204 });
}

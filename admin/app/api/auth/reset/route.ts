import { assertSameOrigin, clearPendingAdmin } from "@/lib/auth";

export async function POST(request: Request) {
  if (!assertSameOrigin(request)) {
    return Response.json({ error: "不正なリクエストです。" }, { status: 403 });
  }
  await clearPendingAdmin();
  return Response.json({ reset: true });
}

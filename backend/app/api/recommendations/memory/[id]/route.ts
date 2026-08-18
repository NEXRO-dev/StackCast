import { authenticatedUserID } from "@/lib/auth/authenticated-user";
import { errorResponse } from "@/lib/auth/response";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const userID = await authenticatedUserID(request);
  if (!userID) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
  const { id } = await params;
  await getTurso().run("DELETE FROM user_memory_items WHERE id = ? AND user_id = ?", id, userID);
  return Response.json({ success: true });
}

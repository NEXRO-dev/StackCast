import { errorResponse } from "@/lib/auth/response";

export const runtime = "nodejs";

export async function POST() {
  return errorResponse(
    "email_verification_required",
    "Request and verify an email code before creating an account.",
    410,
  );
}

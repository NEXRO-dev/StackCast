import {
  clearGoogleOAuth,
  completeGoogleOAuth,
  createPendingAdmin,
} from "@/lib/auth";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const providerError = url.searchParams.get("error");

  if (providerError || !code || !state) {
    await clearGoogleOAuth();
    return Response.redirect(new URL("/login?error=google_cancelled", request.url), 302);
  }

  try {
    const identity = await completeGoogleOAuth(request, code, state);
    await createPendingAdmin(identity);
    await clearGoogleOAuth();
    return Response.redirect(new URL("/login", request.url), 302);
  } catch (error) {
    console.error("Admin Google OAuth callback failed", error);
    await clearGoogleOAuth();
    return Response.redirect(new URL("/login?error=google_failed", request.url), 302);
  }
}

import { beginGoogleOAuth } from "@/lib/auth";

export const runtime = "nodejs";

export async function GET(request: Request) {
  try {
    const authorizationURL = await beginGoogleOAuth(request);
    return Response.redirect(authorizationURL, 302);
  } catch (error) {
    console.error("Unable to start Google OAuth", error);
    return Response.redirect(new URL("/login?error=configuration", request.url), 302);
  }
}

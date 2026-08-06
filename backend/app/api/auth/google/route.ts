import {
  signInWithSocialIdentity,
  SocialAccountError,
} from "@/lib/auth/account";
import { errorResponse } from "@/lib/auth/response";
import { verifyGoogleIdentityToken } from "@/lib/auth/social";
import { validateGoogleAuthInput } from "@/lib/auth/validation";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const input = validateGoogleAuthInput(
    await request.json().catch(() => null),
  );
  if (!input) {
    return errorResponse("invalid_input", "Google token is missing.", 400);
  }

  try {
    const identity = await verifyGoogleIdentityToken(input.identityToken);
    return await signInWithSocialIdentity({
      provider: "google",
      ...identity,
      profileImageURL: identity.profileImageURL ?? input.profileImageURL,
    });
  } catch (error) {
    if (error instanceof SocialAccountError) {
      return errorResponse(error.code, error.message, error.status);
    }
    if (error instanceof Error && error.message.startsWith("Missing required")) {
      console.error("Google authentication configuration failed", error);
      return errorResponse("server_configuration", "Google is not configured.", 503);
    }
    console.error("Google authentication failed", error);
    return errorResponse(
      "invalid_provider_token",
      "Google authentication could not be verified.",
      401,
    );
  }
}

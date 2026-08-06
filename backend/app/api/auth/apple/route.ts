import {
  signInWithSocialIdentity,
  SocialAccountError,
} from "@/lib/auth/account";
import { errorResponse } from "@/lib/auth/response";
import { verifyAppleIdentityToken } from "@/lib/auth/social";
import { validateAppleAuthInput } from "@/lib/auth/validation";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const input = validateAppleAuthInput(
    await request.json().catch(() => null),
  );
  if (!input) {
    return errorResponse("invalid_input", "Apple credential is missing.", 400);
  }

  try {
    const identity = await verifyAppleIdentityToken(
      input.identityToken,
      input.rawNonce,
    );
    return await signInWithSocialIdentity({
      provider: "apple",
      ...identity,
      name: input.name,
    });
  } catch (error) {
    if (error instanceof SocialAccountError) {
      return errorResponse(error.code, error.message, error.status);
    }
    console.error("Apple authentication failed", error);
    return errorResponse(
      "invalid_provider_token",
      "Apple authentication could not be verified.",
      401,
    );
  }
}

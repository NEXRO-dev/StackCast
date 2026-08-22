export type AuthUser = {
  id: string;
  name: string;
  email: string;
  profileImageURL: string | null;
  preferredLanguage: "japanese" | "english";
};

export function authResponse(
  user: AuthUser,
  token: string,
  expiresAt: string,
  requiresProfileSetup = false,
  status = 200,
): Response {
  return Response.json(
    {
      mode: "signedIn",
      user,
      session: { token, expiresAt },
      requiresProfileSetup,
    },
    { status },
  );
}

export function errorResponse(
  code: string,
  message: string,
  status: number,
): Response {
  return Response.json({ error: { code, message } }, { status });
}

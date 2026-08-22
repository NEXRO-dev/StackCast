import { randomBytes, randomUUID } from "node:crypto";
import { authResponse, type AuthUser } from "@/lib/auth/response";
import { createSession } from "@/lib/auth/session";
import { getTurso } from "@/lib/turso";

export type SocialProvider = "google" | "apple";

type IdentityUserRow = AuthUser & {
  user_id: string;
};

export async function signInWithSocialIdentity(input: {
  provider: SocialProvider;
  subject: string;
  email: string | null;
  name: string | null;
  profileImageURL: string | null;
  preferredLanguage: "japanese" | "english";
}): Promise<Response> {
  const existingIdentity = await findIdentity(input.provider, input.subject);

  if (existingIdentity) {
    const user = await updateSocialProfileImage(existingIdentity, input);
    return createAuthenticatedResponse(user, !(await hasCompletedProfile(user.id)));
  }

  if (!input.email) {
    throw new SocialAccountError(
      "provider_email_missing",
      "The provider did not return an email address for this new account.",
      400,
    );
  }

  const existingUser = (await getTurso().get(
    `SELECT users.id, users.name, users.email,
            users.preferred_language AS preferredLanguage,
            user_profiles.profile_image_url AS profileImageURL
     FROM users
     LEFT JOIN user_profiles ON user_profiles.user_id = users.id
     WHERE users.email = ? LIMIT 1`,
    input.email,
  )) as AuthUser | null;
  const now = new Date().toISOString();
  const user: AuthUser =
    existingUser ?? {
      id: randomUUID(),
      name: normalizedName(input.name, input.email),
      email: input.email,
      profileImageURL: input.profileImageURL,
      preferredLanguage: input.preferredLanguage,
    };
  const session = createSession();
  const statements = [];

  if (!existingUser) {
    statements.push({
      sql: `INSERT INTO users
        (id, name, email, password_hash, preferred_language, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)`,
      args: [
        user.id,
        user.name,
        user.email,
        `external$${randomBytes(32).toString("base64url")}`,
        user.preferredLanguage,
        now,
        now,
      ],
    });
  }

  if (input.profileImageURL) {
    statements.push(profileImageUpsert(user.id, input.profileImageURL, now));
    user.profileImageURL = input.profileImageURL;
  }

  statements.push(
    {
      sql: `INSERT INTO auth_identities
        (id, user_id, provider, provider_subject, provider_email, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)`,
      args: [
        randomUUID(),
        user.id,
        input.provider,
        input.subject,
        input.email,
        now,
        now,
      ],
    },
    sessionInsert(user.id, session),
  );

  try {
    await getTurso().batch(statements, "immediate");
    return authResponse(
      user,
      session.token,
      session.expiresAt,
      !(await hasCompletedProfile(user.id)),
    );
  } catch (error) {
    const racedIdentity = await findIdentity(input.provider, input.subject);
    if (racedIdentity) {
      return createAuthenticatedResponse(racedIdentity);
    }
    throw error;
  }
}

export async function createAuthenticatedResponse(user: AuthUser, requiresProfileSetup = false): Promise<Response> {
  const session = createSession();
  const insert = sessionInsert(user.id, session);
  await getTurso().run(
    insert.sql,
    ...insert.args,
  );
  return authResponse(user, session.token, session.expiresAt, requiresProfileSetup);
}

export class SocialAccountError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

async function findIdentity(
  provider: SocialProvider,
  subject: string,
): Promise<AuthUser | null> {
  const row = (await getTurso().get(
    `SELECT users.id, users.name, users.email,
            users.preferred_language AS preferredLanguage,
            user_profiles.profile_image_url AS profileImageURL,
            auth_identities.user_id
     FROM auth_identities
     JOIN users ON users.id = auth_identities.user_id
     LEFT JOIN user_profiles ON user_profiles.user_id = users.id
     WHERE auth_identities.provider = ?
       AND auth_identities.provider_subject = ?
     LIMIT 1`,
    provider,
    subject,
  )) as IdentityUserRow | null;

  return row
    ? {
        id: row.id,
        name: row.name,
        email: row.email,
        profileImageURL: row.profileImageURL,
        preferredLanguage: row.preferredLanguage,
      }
    : null;
}

async function updateSocialProfileImage(
  user: AuthUser,
  input: { provider: SocialProvider; profileImageURL: string | null },
): Promise<AuthUser> {
  if (input.provider !== "google" || !input.profileImageURL) {
    return user;
  }

  const statement = profileImageUpsert(
    user.id,
    input.profileImageURL,
    new Date().toISOString(),
  );
  await getTurso().run(
    statement.sql,
    ...statement.args,
  );
  return { ...user, profileImageURL: input.profileImageURL };
}

function profileImageUpsert(userId: string, imageURL: string, updatedAt: string) {
  return {
    sql: `INSERT INTO user_profiles (user_id, profile_image_url, updated_at)
          VALUES (?, ?, ?)
          ON CONFLICT(user_id) DO UPDATE SET
            profile_image_url = excluded.profile_image_url,
            updated_at = excluded.updated_at`,
    args: [userId, imageURL, updatedAt],
  };
}

function sessionInsert(userId: string, session: ReturnType<typeof createSession>) {
  return {
    sql: `INSERT INTO auth_sessions
      (id, user_id, token_hash, expires_at, created_at, last_used_at)
      VALUES (?, ?, ?, ?, ?, ?)`,
    args: [
      session.id,
      userId,
      session.tokenHash,
      session.expiresAt,
      session.createdAt,
      session.createdAt,
    ],
  };
}

function normalizedName(name: string | null, email: string): string {
  const trimmed = name?.trim().slice(0, 100);
  if (trimmed) {
    return trimmed;
  }
  return email.split("@")[0]?.slice(0, 100) || "StackCast User";
}

async function hasCompletedProfile(userID: string): Promise<boolean> {
  const row = (await getTurso().get(
    `SELECT onboarding_completed_at AS onboardingCompletedAt
     FROM user_recommendation_profiles WHERE user_id = ? LIMIT 1`,
    userID,
  )) as { onboardingCompletedAt?: string | null } | null;
  return Boolean(row?.onboardingCompletedAt);
}

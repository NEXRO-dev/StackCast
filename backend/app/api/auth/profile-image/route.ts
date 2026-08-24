import { storeUserProfileImage, signedR2ObjectURL } from "@/lib/r2-storage";
import { errorResponse } from "@/lib/auth/response";
import { bearerToken, hashSessionToken } from "@/lib/auth/session";
import { getTurso } from "@/lib/turso";

export const runtime = "nodejs";

type ProfileRow = {
  userID: string;
  profileImageURL: string | null;
  profileImageObjectKey: string | null;
  canEditProfileImage: number;
  canChangePassword: number;
};

async function currentProfile(request: Request): Promise<ProfileRow | null> {
  const token = bearerToken(request);
  if (!token) return null;
  return (await getTurso().get(
    `SELECT users.id AS userID,
            user_profiles.profile_image_url AS profileImageURL,
            user_profiles.profile_image_object_key AS profileImageObjectKey,
            1 AS canEditProfileImage,
            CASE WHEN users.password_hash NOT LIKE 'external$%' THEN 1 ELSE 0 END AS canChangePassword
     FROM auth_sessions
     JOIN users ON users.id = auth_sessions.user_id
     LEFT JOIN user_profiles ON user_profiles.user_id = users.id
     WHERE auth_sessions.token_hash = ?
       AND auth_sessions.expires_at > ?
     LIMIT 1`,
    hashSessionToken(token),
    new Date().toISOString(),
  )) as ProfileRow | null;
}

export async function GET(request: Request) {
  try {
    const profile = await currentProfile(request);
    if (!profile) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
    return Response.json({
      canEditProfileImage: Boolean(profile.canEditProfileImage),
      canChangePassword: Boolean(profile.canChangePassword),
      profileImageURL: profile.profileImageURL,
    });
  } catch (error) {
    console.error("Profile image permission lookup failed", error);
    return errorResponse("server_error", "Unable to load profile image settings.", 500);
  }
}

export async function POST(request: Request) {
  try {
    const profile = await currentProfile(request);
    if (!profile) return errorResponse("unauthorized", "Session is invalid or expired.", 401);
    if (!profile.canEditProfileImage) {
      return errorResponse("profile_image_not_allowed", "This sign-in method cannot set a profile image.", 403);
    }

    const form = await request.formData();
    const file = form.get("image");
    if (!(file instanceof File)) {
      return errorResponse("invalid_input", "A profile image is required.", 400);
    }
    if (!["image/jpeg", "image/png", "image/webp"].includes(file.type)) {
      return errorResponse("invalid_input", "Use a JPEG, PNG, or WebP image.", 400);
    }
    if (file.size > 5 * 1024 * 1024) {
      return errorResponse("invalid_input", "Profile images must be 5 MB or smaller.", 400);
    }

    const objectKey = await storeUserProfileImage(
      profile.userID,
      new Uint8Array(await file.arrayBuffer()),
      file.type,
    );
    const now = new Date().toISOString();
    const profileImageURL = new URL(`/api/auth/profile-image/${profile.userID}`, request.url);
    profileImageURL.searchParams.set("v", now);
    await getTurso().run(
      `INSERT INTO user_profiles (user_id, profile_image_url, profile_image_object_key, updated_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(user_id) DO UPDATE SET
         profile_image_url = excluded.profile_image_url,
         profile_image_object_key = excluded.profile_image_object_key,
         updated_at = excluded.updated_at`,
      profile.userID,
      profileImageURL.toString(),
      objectKey,
      now,
    );
    return Response.json({ profileImageURL: profileImageURL.toString() });
  } catch (error) {
    console.error("Profile image upload failed", error);
    return errorResponse("server_error", "Unable to save profile image.", 500);
  }
}

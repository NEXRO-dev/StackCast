import {
  DeleteObjectsCommand,
  GetObjectCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
  type ObjectIdentifier,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

let client: S3Client | undefined;

function requiredEnvironmentVariable(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`MISSING_ENV_${name}`);
  return value;
}

function getClient(): S3Client {
  if (client) return client;

  client = new S3Client({
    region: "auto",
    endpoint: requiredEnvironmentVariable("R2_ENDPOINT"),
    credentials: {
      accessKeyId: requiredEnvironmentVariable("R2_ACCESS_KEY_ID"),
      secretAccessKey: requiredEnvironmentVariable("R2_SECRET_ACCESS_KEY"),
    },
  });
  return client;
}

/** Delete every generated audio object belonging to a user. */
export async function deleteUserAudioObjects(userID: string): Promise<number> {
  const bucket = requiredEnvironmentVariable("R2_BUCKET_NAME");
  const prefix = `casts/${userID}/`;
  const objects: ObjectIdentifier[] = [];
  let continuationToken: string | undefined;

  do {
    const result = await getClient().send(new ListObjectsV2Command({
      Bucket: bucket,
      Prefix: prefix,
      ContinuationToken: continuationToken,
    }));

    for (const object of result.Contents ?? []) {
      if (object.Key) objects.push({ Key: object.Key });
    }

    continuationToken = result.IsTruncated ? result.NextContinuationToken : undefined;
  } while (continuationToken);

  for (let index = 0; index < objects.length; index += 1_000) {
    await getClient().send(new DeleteObjectsCommand({
      Bucket: bucket,
      Delete: { Objects: objects.slice(index, index + 1_000), Quiet: true },
    }));
  }

  return objects.length;
}

export async function storeUserProfileImage(
  userID: string,
  body: Uint8Array,
  contentType: string,
): Promise<string> {
  const objectKey = `profiles/${userID}/avatar`;
  await getClient().send(new PutObjectCommand({
    Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"),
    Key: objectKey,
    Body: body,
    ContentType: contentType,
    CacheControl: "private, max-age=86400",
  }));
  return objectKey;
}

export async function signedR2ObjectURL(objectKey: string): Promise<string> {
  return getSignedUrl(
    getClient(),
    new GetObjectCommand({
      Bucket: requiredEnvironmentVariable("R2_BUCKET_NAME"),
      Key: objectKey,
    }),
    { expiresIn: 60 * 60 },
  );
}

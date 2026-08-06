import {
  randomBytes,
  scrypt as nodeScrypt,
  timingSafeEqual,
} from "node:crypto";
const keyLength = 64;
const cost = 2 ** 15;
const blockSize = 8;
const parallelization = 3;
const maxMemory = 64 * 1024 * 1024;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const derivedKey = await deriveKey(password, salt, keyLength, {
    N: cost,
    r: blockSize,
    p: parallelization,
    maxmem: maxMemory,
  });

  return [
    "scrypt",
    cost,
    blockSize,
    parallelization,
    salt.toString("base64url"),
    derivedKey.toString("base64url"),
  ].join("$");
}

export async function verifyPassword(
  password: string,
  encodedHash: string,
): Promise<boolean> {
  const [algorithm, costValue, blockValue, parallelValue, saltValue, hashValue] =
    encodedHash.split("$");

  if (
    algorithm !== "scrypt" ||
    !costValue ||
    !blockValue ||
    !parallelValue ||
    !saltValue ||
    !hashValue
  ) {
    return false;
  }

  const expectedHash = Buffer.from(hashValue, "base64url");
  const derivedKey = await deriveKey(
    password,
    Buffer.from(saltValue, "base64url"),
    expectedHash.length,
    {
      N: Number(costValue),
      r: Number(blockValue),
      p: Number(parallelValue),
      maxmem: maxMemory,
    },
  );

  return (
    expectedHash.length === derivedKey.length &&
    timingSafeEqual(expectedHash, derivedKey)
  );
}

function deriveKey(
  password: string,
  salt: Buffer,
  length: number,
  options: { N: number; r: number; p: number; maxmem: number },
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    nodeScrypt(password, salt, length, options, (error, derivedKey) => {
      if (error) {
        reject(error);
        return;
      }

      resolve(derivedKey);
    });
  });
}

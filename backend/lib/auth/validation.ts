export type SignupInput = {
  name: string;
  email: string;
  password: string;
};

export type LoginInput = {
  email: string;
  password: string;
};

export type EmailRequestInput = {
  email: string;
};

export type EmailCodeInput = {
  email: string;
  code: string;
};

export type CompleteEnrollmentInput = {
  enrollmentToken: string;
  name: string;
  password: string;
};

export type GoogleAuthInput = {
  identityToken: string;
  profileImageURL: string | null;
};

export type AppleAuthInput = {
  identityToken: string;
  rawNonce: string;
  name: string | null;
};

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const passwordPattern = /^(?=.*[A-Za-z])(?=.*\d)(?=.*[^A-Za-z\d]).{8,128}$/;

export function validateSignupInput(value: unknown): SignupInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const name = normalizedString(value.name);
  const email = normalizedEmail(value.email);
  const password = typeof value.password === "string" ? value.password : "";

  if (
    name.length < 1 ||
    name.length > 100 ||
    !isValidEmail(email) ||
    !passwordPattern.test(password)
  ) {
    return null;
  }

  return { name, email, password };
}

export function validateLoginInput(value: unknown): LoginInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const email = normalizedEmail(value.email);
  const password = typeof value.password === "string" ? value.password : "";

  if (!isValidEmail(email) || password.length < 1 || password.length > 128) {
    return null;
  }

  return { email, password };
}

export function validateEmailRequestInput(value: unknown): EmailRequestInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const email = normalizedEmail(value.email);
  return isValidEmail(email) ? { email } : null;
}

export function validateEmailCodeInput(value: unknown): EmailCodeInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const email = normalizedEmail(value.email);
  const code = typeof value.code === "string" ? value.code.trim() : "";
  return isValidEmail(email) && /^\d{6}$/.test(code) ? { email, code } : null;
}

export function validateCompleteEnrollmentInput(
  value: unknown,
): CompleteEnrollmentInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const enrollmentToken = normalizedString(value.enrollmentToken);
  const name = normalizedString(value.name);
  const password = typeof value.password === "string" ? value.password : "";

  if (
    enrollmentToken.length < 32 ||
    enrollmentToken.length > 256 ||
    name.length < 1 ||
    name.length > 100 ||
    !passwordPattern.test(password)
  ) {
    return null;
  }

  return { enrollmentToken, name, password };
}

export function validateGoogleAuthInput(value: unknown): GoogleAuthInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const identityToken = normalizedString(value.identityToken);
  const profileImageURL = normalizedGoogleProfileImageURL(value.profileImageURL);
  return identityToken.length >= 100
    ? { identityToken, profileImageURL }
    : null;
}

export function validateAppleAuthInput(value: unknown): AppleAuthInput | null {
  if (!isRecord(value)) {
    return null;
  }

  const identityToken = normalizedString(value.identityToken);
  const rawNonce = normalizedString(value.rawNonce);
  const name = normalizedString(value.name) || null;

  if (identityToken.length < 100 || rawNonce.length < 32 || rawNonce.length > 256) {
    return null;
  }

  return { identityToken, rawNonce, name };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function normalizedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizedEmail(value: unknown): string {
  return normalizedString(value).toLocaleLowerCase("en-US");
}

function isValidEmail(email: string): boolean {
  return email.length <= 254 && emailPattern.test(email);
}

function normalizedGoogleProfileImageURL(value: unknown): string | null {
  const candidate = normalizedString(value);
  if (!candidate || candidate.length > 2048) {
    return null;
  }

  try {
    const url = new URL(candidate);
    const hostname = url.hostname.toLocaleLowerCase("en-US");
    const isGoogleImageHost =
      hostname === "googleusercontent.com" ||
      hostname.endsWith(".googleusercontent.com");
    return url.protocol === "https:" && isGoogleImageHost
      ? url.toString()
      : null;
  } catch {
    return null;
  }
}

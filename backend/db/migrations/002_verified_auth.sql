CREATE TABLE IF NOT EXISTS auth_email_challenges (
  id TEXT PRIMARY KEY NOT NULL,
  email TEXT NOT NULL COLLATE NOCASE,
  code_hash TEXT NOT NULL,
  requester_hash TEXT NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS auth_email_challenges_email_created_idx
  ON auth_email_challenges(email, created_at DESC);

CREATE INDEX IF NOT EXISTS auth_email_challenges_requester_created_idx
  ON auth_email_challenges(requester_hash, created_at DESC);

CREATE TABLE IF NOT EXISTS auth_enrollment_tokens (
  id TEXT PRIMARY KEY NOT NULL,
  email TEXT NOT NULL COLLATE NOCASE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TEXT NOT NULL,
  consumed_at TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS auth_enrollment_tokens_email_idx
  ON auth_enrollment_tokens(email);

CREATE TABLE IF NOT EXISTS auth_identities (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  provider TEXT NOT NULL CHECK (provider IN ('google', 'apple')),
  provider_subject TEXT NOT NULL,
  provider_email TEXT COLLATE NOCASE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (provider, provider_subject),
  UNIQUE (user_id, provider)
);

CREATE INDEX IF NOT EXISTS auth_identities_user_id_idx
  ON auth_identities(user_id);

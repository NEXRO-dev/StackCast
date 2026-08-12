CREATE TABLE IF NOT EXISTS cast_shares (
  cast_id TEXT PRIMARY KEY NOT NULL,
  token TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (cast_id) REFERENCES casts(id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS cast_shares_token_idx
  ON cast_shares(token);

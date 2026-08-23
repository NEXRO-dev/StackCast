CREATE TABLE IF NOT EXISTS push_device_tokens (
  token TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS push_device_tokens_user_id_idx
  ON push_device_tokens(user_id);

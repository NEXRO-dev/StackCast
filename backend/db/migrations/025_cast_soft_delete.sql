ALTER TABLE casts ADD COLUMN deleted_at TEXT;

CREATE INDEX IF NOT EXISTS casts_deleted_at_idx
  ON casts(deleted_at);

CREATE TABLE IF NOT EXISTS cast_reports (
  id TEXT PRIMARY KEY NOT NULL,
  cast_id TEXT NOT NULL,
  share_token TEXT NOT NULL,
  reason TEXT NOT NULL,
  details TEXT,
  reporter_key TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TEXT NOT NULL,
  reviewed_at TEXT,
  FOREIGN KEY (cast_id) REFERENCES casts(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS cast_reports_status_created_idx
  ON cast_reports(status, created_at);


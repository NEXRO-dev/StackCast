PRAGMA foreign_keys = OFF;

CREATE TABLE casts_new (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
  summary TEXT,
  transcript TEXT,
  duration_minutes INTEGER NOT NULL DEFAULT 10
    CHECK (duration_minutes IN (2, 5, 10, 15, 20)),
  language TEXT NOT NULL DEFAULT 'japanese'
    CHECK (language IN ('japanese', 'english')),
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
  audio_object_key TEXT,
  audio_url TEXT,
  audio_content_type TEXT DEFAULT 'audio/mpeg',
  credit_cost INTEGER NOT NULL DEFAULT 2 CHECK (credit_cost > 0),
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  completed_at TEXT,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

INSERT INTO casts_new (
  id, user_id, title, summary, transcript, duration_minutes, language, status,
  audio_object_key, audio_url, audio_content_type, credit_cost, error_message,
  created_at, updated_at, completed_at
)
SELECT
  id, user_id, title, summary, transcript, duration_minutes, language, status,
  audio_object_key, audio_url, audio_content_type, credit_cost, error_message,
  created_at, updated_at, completed_at
FROM casts;

DROP TABLE casts;
ALTER TABLE casts_new RENAME TO casts;

CREATE INDEX casts_user_id_created_at_idx
  ON casts(user_id, created_at DESC);

CREATE INDEX casts_user_id_status_idx
  ON casts(user_id, status, created_at DESC);

PRAGMA foreign_keys = ON;

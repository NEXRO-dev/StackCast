CREATE TABLE IF NOT EXISTS saved_articles (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  canonical_url TEXT NOT NULL,
  title TEXT NOT NULL,
  source TEXT NOT NULL,
  saved_at TEXT NOT NULL,
  state TEXT NOT NULL DEFAULT 'unread' CHECK (state IN ('unread', 'inProgress', 'completed')),
  completed_at TEXT,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (user_id, canonical_url)
);

CREATE INDEX IF NOT EXISTS saved_articles_user_updated_idx
  ON saved_articles(user_id, updated_at DESC);

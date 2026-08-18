CREATE TABLE IF NOT EXISTS user_custom_interests (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  label TEXT NOT NULL,
  normalized_label TEXT NOT NULL,
  matched_topic_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(user_id, normalized_label),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (matched_topic_id) REFERENCES recommendation_topics(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS user_custom_interests_user_idx
  ON user_custom_interests(user_id, created_at);

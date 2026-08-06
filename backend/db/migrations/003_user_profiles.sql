CREATE TABLE IF NOT EXISTS user_profiles (
  user_id TEXT PRIMARY KEY NOT NULL,
  profile_image_url TEXT NOT NULL CHECK (length(profile_image_url) BETWEEN 1 AND 2048),
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

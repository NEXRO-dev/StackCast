ALTER TABLE users
  ADD COLUMN preferred_language TEXT NOT NULL DEFAULT 'japanese'
  CHECK (preferred_language IN ('japanese', 'english'));

ALTER TABLE casts
  ADD COLUMN language TEXT NOT NULL DEFAULT 'japanese'
  CHECK (language IN ('japanese', 'english'));

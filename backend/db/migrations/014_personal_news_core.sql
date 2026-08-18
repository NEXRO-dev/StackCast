CREATE TABLE IF NOT EXISTS recommendation_topics (
  id TEXT PRIMARY KEY NOT NULL,
  name_ja TEXT NOT NULL,
  name_en TEXT NOT NULL,
  query_en TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_recommendation_profiles (
  user_id TEXT PRIMARY KEY NOT NULL,
  age_band TEXT NOT NULL DEFAULT 'unspecified',
  gender TEXT,
  personalization_enabled INTEGER NOT NULL DEFAULT 1 CHECK (personalization_enabled IN (0, 1)),
  daily_auto_cast_enabled INTEGER NOT NULL DEFAULT 0 CHECK (daily_auto_cast_enabled IN (0, 1)),
  daily_cast_duration_minutes INTEGER NOT NULL DEFAULT 5 CHECK (daily_cast_duration_minutes IN (5, 10, 15, 20)),
  ai_processing_consent_at TEXT,
  onboarding_completed_at TEXT,
  memory_version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS user_topic_preferences (
  user_id TEXT NOT NULL,
  topic_id TEXT NOT NULL,
  preference TEXT NOT NULL DEFAULT 'like' CHECK (preference IN ('like', 'neutral', 'avoid')),
  weight REAL NOT NULL DEFAULT 1 CHECK (weight >= 0 AND weight <= 1),
  source TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('onboarding', 'manual')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, topic_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (topic_id) REFERENCES recommendation_topics(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS news_articles (
  id TEXT PRIMARY KEY NOT NULL,
  canonical_url TEXT NOT NULL UNIQUE,
  original_url TEXT NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  source_domain TEXT NOT NULL,
  language TEXT NOT NULL DEFAULT 'unknown',
  country TEXT,
  published_at TEXT NOT NULL,
  provider TEXT NOT NULL,
  provider_id TEXT,
  content_hash TEXT,
  quality_score REAL NOT NULL DEFAULT 0.5 CHECK (quality_score >= 0 AND quality_score <= 1),
  fetched_at TEXT NOT NULL,
  expires_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS news_articles_published_at_idx ON news_articles(published_at DESC);
CREATE INDEX IF NOT EXISTS news_articles_source_domain_idx ON news_articles(source_domain);
CREATE INDEX IF NOT EXISTS news_articles_expires_at_idx ON news_articles(expires_at);

CREATE TABLE IF NOT EXISTS news_article_topics (
  article_id TEXT NOT NULL,
  topic_id TEXT NOT NULL,
  score REAL NOT NULL DEFAULT 1 CHECK (score >= 0 AND score <= 1),
  source TEXT NOT NULL DEFAULT 'provider',
  PRIMARY KEY (article_id, topic_id),
  FOREIGN KEY (article_id) REFERENCES news_articles(id) ON DELETE CASCADE,
  FOREIGN KEY (topic_id) REFERENCES recommendation_topics(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS news_article_topics_topic_idx ON news_article_topics(topic_id, score DESC);

CREATE TABLE IF NOT EXISTS recommendation_events (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  article_id TEXT NOT NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('impression', 'open', 'dwell', 'save', 'unsave', 'dislike', 'mute_topic', 'mute_source', 'add_to_cast', 'cast_created', 'cast_completed')),
  surface TEXT NOT NULL DEFAULT 'home' CHECK (surface IN ('home', 'stock', 'cast')),
  session_id TEXT,
  dwell_ms INTEGER,
  position INTEGER,
  metadata_json TEXT,
  occurred_at TEXT NOT NULL,
  received_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (article_id) REFERENCES news_articles(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS recommendation_events_user_time_idx ON recommendation_events(user_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS recommendation_events_article_type_idx ON recommendation_events(article_id, event_type);

CREATE TABLE IF NOT EXISTS user_memory_items (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('topic', 'source', 'keyword')),
  value TEXT NOT NULL,
  polarity TEXT NOT NULL CHECK (polarity IN ('positive', 'negative')),
  weight REAL NOT NULL CHECK (weight >= 0 AND weight <= 1),
  origin TEXT NOT NULL CHECK (origin IN ('explicit', 'behavior')),
  reason TEXT NOT NULL,
  last_event_at TEXT NOT NULL,
  expires_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (user_id, kind, value),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS user_memory_items_user_idx ON user_memory_items(user_id, weight DESC);

CREATE TABLE IF NOT EXISTS daily_news_editions (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  edition_date TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('building', 'ready', 'fallback', 'failed')),
  cast_id TEXT,
  auto_cast_status TEXT NOT NULL DEFAULT 'disabled' CHECK (auto_cast_status IN ('disabled', 'queued', 'processing', 'ready', 'skipped', 'failed')),
  skip_reason TEXT,
  generated_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (user_id, edition_date),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (cast_id) REFERENCES casts(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS daily_news_editions_date_idx ON daily_news_editions(edition_date, status);

CREATE TABLE IF NOT EXISTS daily_news_edition_items (
  edition_id TEXT NOT NULL,
  article_id TEXT NOT NULL,
  rank INTEGER NOT NULL CHECK (rank BETWEEN 1 AND 5),
  score REAL NOT NULL,
  reason_code TEXT NOT NULL,
  reason_text_ja TEXT NOT NULL,
  reason_text_en TEXT NOT NULL,
  PRIMARY KEY (edition_id, article_id),
  UNIQUE (edition_id, rank),
  FOREIGN KEY (edition_id) REFERENCES daily_news_editions(id) ON DELETE CASCADE,
  FOREIGN KEY (article_id) REFERENCES news_articles(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS news_article_ai_cache (
  article_id TEXT NOT NULL,
  language TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  summary TEXT NOT NULL,
  script_segment TEXT NOT NULL,
  model TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('ready', 'failed')),
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  PRIMARY KEY (article_id, language, content_hash),
  FOREIGN KEY (article_id) REFERENCES news_articles(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS daily_cast_jobs (
  id TEXT PRIMARY KEY NOT NULL,
  edition_id TEXT NOT NULL UNIQUE,
  user_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('queued', 'processing', 'retry_wait', 'completed', 'failed')),
  stage TEXT NOT NULL CHECK (stage IN ('fetch', 'summarize', 'script', 'audio', 'persist')),
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  lease_until TEXT,
  error_code TEXT,
  cast_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (edition_id) REFERENCES daily_news_editions(id) ON DELETE CASCADE,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (cast_id) REFERENCES casts(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS daily_cast_jobs_queue_idx ON daily_cast_jobs(status, next_attempt_at, created_at);

INSERT OR IGNORE INTO recommendation_topics
  (id, name_ja, name_en, query_en, is_active, sort_order, created_at, updated_at)
VALUES
  ('technology', 'テクノロジー', 'Technology', '(technology OR AI OR software)', 1, 10, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('business', 'ビジネス', 'Business', '(business OR economy OR markets)', 1, 20, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('science', '科学', 'Science', '(science OR research OR discovery)', 1, 30, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('entertainment', 'エンタメ', 'Entertainment', '(entertainment OR film OR music)', 1, 40, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('sports', 'スポーツ', 'Sports', '(sports OR athlete OR tournament)', 1, 50, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('society', '社会', 'Society', '(society OR education OR community)', 1, 60, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('world', '国際', 'World', '(international OR diplomacy OR geopolitics)', 1, 70, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('health', '健康', 'Health', '(health OR medicine OR wellness)', 1, 80, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
  ('culture', '文化', 'Culture', '(culture OR art OR history)', 1, 90, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

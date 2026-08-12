CREATE TABLE IF NOT EXISTS casts (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  title TEXT NOT NULL CHECK (length(title) BETWEEN 1 AND 200),
  summary TEXT,
  duration_minutes INTEGER NOT NULL DEFAULT 10
    CHECK (duration_minutes IN (5, 10, 15, 20)),
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

CREATE INDEX IF NOT EXISTS casts_user_id_created_at_idx
  ON casts(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS casts_user_id_status_idx
  ON casts(user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS cast_sources (
  id TEXT PRIMARY KEY NOT NULL,
  cast_id TEXT NOT NULL,
  source_order INTEGER NOT NULL CHECK (source_order >= 0),
  source_url TEXT NOT NULL CHECK (length(source_url) BETWEEN 1 AND 4000),
  source_title TEXT,
  source_text TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (cast_id) REFERENCES casts(id) ON DELETE CASCADE,
  UNIQUE (cast_id, source_order)
);

CREATE INDEX IF NOT EXISTS cast_sources_cast_id_idx
  ON cast_sources(cast_id, source_order);

CREATE TABLE IF NOT EXISTS cast_generation_jobs (
  id TEXT PRIMARY KEY NOT NULL,
  cast_id TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'processing', 'completed', 'failed')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error TEXT,
  queued_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  FOREIGN KEY (cast_id) REFERENCES casts(id) ON DELETE CASCADE,
  UNIQUE (cast_id)
);

CREATE INDEX IF NOT EXISTS cast_generation_jobs_status_idx
  ON cast_generation_jobs(status, queued_at);

CREATE TABLE IF NOT EXISTS user_credit_periods (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  plan_tier TEXT NOT NULL DEFAULT 'free'
    CHECK (plan_tier IN ('free', 'plus', 'pro', 'lifetime')),
  credit_limit INTEGER NOT NULL DEFAULT 3 CHECK (credit_limit >= 0),
  credits_reserved INTEGER NOT NULL DEFAULT 0 CHECK (credits_reserved >= 0),
  credits_used INTEGER NOT NULL DEFAULT 0 CHECK (credits_used >= 0),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (user_id, period_start, period_end)
);

CREATE INDEX IF NOT EXISTS user_credit_periods_active_idx
  ON user_credit_periods(user_id, period_start, period_end);

CREATE TABLE IF NOT EXISTS cast_credit_ledger (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  cast_id TEXT,
  credit_period_id TEXT NOT NULL,
  amount INTEGER NOT NULL CHECK (amount != 0),
  entry_type TEXT NOT NULL
    CHECK (entry_type IN ('reserve', 'consume', 'release', 'adjustment')),
  idempotency_key TEXT NOT NULL UNIQUE,
  note TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (cast_id) REFERENCES casts(id) ON DELETE SET NULL,
  FOREIGN KEY (credit_period_id) REFERENCES user_credit_periods(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS cast_credit_ledger_user_created_at_idx
  ON cast_credit_ledger(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS cast_credit_ledger_cast_id_idx
  ON cast_credit_ledger(cast_id);

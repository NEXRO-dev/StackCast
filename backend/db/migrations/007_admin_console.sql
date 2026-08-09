CREATE TABLE IF NOT EXISTS admin_plan_overrides (
  user_id TEXT PRIMARY KEY NOT NULL,
  plan_tier TEXT NOT NULL
    CHECK (plan_tier IN ('free', 'plus', 'pro')),
  is_active INTEGER NOT NULL DEFAULT 0
    CHECK (is_active IN (0, 1)),
  expires_at TEXT,
  reason TEXT NOT NULL CHECK (length(reason) BETWEEN 3 AND 500),
  updated_by TEXT NOT NULL COLLATE NOCASE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS admin_plan_overrides_expires_at_idx
  ON admin_plan_overrides(expires_at);

CREATE TABLE IF NOT EXISTS admin_user_metadata (
  user_id TEXT PRIMARY KEY NOT NULL,
  onboarding_status TEXT NOT NULL DEFAULT 'not_started'
    CHECK (onboarding_status IN ('not_started', 'in_progress', 'completed')),
  notes TEXT CHECK (notes IS NULL OR length(notes) <= 2000),
  updated_by TEXT NOT NULL COLLATE NOCASE,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS admin_user_metadata_onboarding_idx
  ON admin_user_metadata(onboarding_status);

CREATE TABLE IF NOT EXISTS admin_audit_logs (
  id TEXT PRIMARY KEY NOT NULL,
  admin_email TEXT NOT NULL COLLATE NOCASE,
  action TEXT NOT NULL,
  target_type TEXT NOT NULL,
  target_id TEXT NOT NULL,
  metadata_json TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS admin_audit_logs_target_idx
  ON admin_audit_logs(target_type, target_id, created_at DESC);

CREATE INDEX IF NOT EXISTS admin_audit_logs_admin_idx
  ON admin_audit_logs(admin_email, created_at DESC);

CREATE TABLE IF NOT EXISTS admin_login_attempts (
  attempt_key TEXT PRIMARY KEY NOT NULL,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  window_started_at TEXT NOT NULL,
  locked_until TEXT,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS admin_login_attempts_locked_until_idx
  ON admin_login_attempts(locked_until);

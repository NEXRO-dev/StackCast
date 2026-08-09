CREATE TABLE IF NOT EXISTS billing_subscriptions (
  id TEXT PRIMARY KEY NOT NULL,
  user_id TEXT NOT NULL,
  revenuecat_app_user_id TEXT NOT NULL,
  entitlement_id TEXT NOT NULL,
  product_id TEXT,
  store TEXT,
  environment TEXT NOT NULL DEFAULT 'test',
  status TEXT NOT NULL DEFAULT 'unknown'
    CHECK (status IN ('active', 'expired', 'cancelled', 'billing_issue', 'paused', 'unknown')),
  is_active INTEGER NOT NULL DEFAULT 0
    CHECK (is_active IN (0, 1)),
  purchased_at TEXT,
  expires_at TEXT,
  cancelled_at TEXT,
  original_transaction_id TEXT,
  store_transaction_id TEXT,
  latest_event_id TEXT UNIQUE,
  raw_event_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  UNIQUE (revenuecat_app_user_id, entitlement_id)
);

CREATE INDEX IF NOT EXISTS billing_subscriptions_user_id_idx
  ON billing_subscriptions(user_id);

CREATE INDEX IF NOT EXISTS billing_subscriptions_active_idx
  ON billing_subscriptions(user_id, is_active);

CREATE INDEX IF NOT EXISTS billing_subscriptions_expires_at_idx
  ON billing_subscriptions(expires_at);

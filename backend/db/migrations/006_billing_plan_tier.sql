ALTER TABLE billing_subscriptions
  ADD COLUMN plan_tier TEXT;

CREATE INDEX IF NOT EXISTS billing_subscriptions_plan_tier_idx
  ON billing_subscriptions(user_id, plan_tier);

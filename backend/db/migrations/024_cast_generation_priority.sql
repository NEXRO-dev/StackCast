ALTER TABLE cast_generation_jobs ADD COLUMN priority INTEGER NOT NULL DEFAULT 0
  CHECK (priority >= 0 AND priority <= 100);

CREATE INDEX IF NOT EXISTS cast_generation_jobs_queue_priority_idx
  ON cast_generation_jobs(status, priority DESC, queued_at);

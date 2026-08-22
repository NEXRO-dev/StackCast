PRAGMA foreign_keys = OFF;

ALTER TABLE user_recommendation_profiles
  RENAME TO user_recommendation_profiles_old_duration_range;

CREATE TABLE user_recommendation_profiles (
  user_id TEXT PRIMARY KEY NOT NULL,
  age_band TEXT NOT NULL DEFAULT 'unspecified',
  gender TEXT,
  personalization_enabled INTEGER NOT NULL DEFAULT 1 CHECK (personalization_enabled IN (0, 1)),
  daily_auto_cast_enabled INTEGER NOT NULL DEFAULT 0 CHECK (daily_auto_cast_enabled IN (0, 1)),
  daily_cast_duration_minutes INTEGER NOT NULL DEFAULT 5 CHECK (daily_cast_duration_minutes BETWEEN 5 AND 20),
  ai_processing_consent_at TEXT,
  onboarding_completed_at TEXT,
  memory_version INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  time_zone TEXT NOT NULL DEFAULT 'Asia/Tokyo',
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

INSERT INTO user_recommendation_profiles (
  user_id,
  age_band,
  gender,
  personalization_enabled,
  daily_auto_cast_enabled,
  daily_cast_duration_minutes,
  ai_processing_consent_at,
  onboarding_completed_at,
  memory_version,
  created_at,
  updated_at,
  time_zone
)
SELECT
  user_id,
  age_band,
  gender,
  personalization_enabled,
  daily_auto_cast_enabled,
  CASE
    WHEN daily_cast_duration_minutes BETWEEN 5 AND 20 THEN daily_cast_duration_minutes
    ELSE 5
  END,
  ai_processing_consent_at,
  onboarding_completed_at,
  memory_version,
  created_at,
  updated_at,
  time_zone
FROM user_recommendation_profiles_old_duration_range;

DROP TABLE user_recommendation_profiles_old_duration_range;

PRAGMA foreign_keys = ON;

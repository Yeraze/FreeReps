-- TimescaleDB-safe historical duplicate cleanup.
--
-- Migration 025 used ctid-based dedup, but ctid is chunk-local in
-- TimescaleDB hypertables — the DELETE matched rows only within a single
-- chunk, leaving cross-chunk duplicates untouched.
--
-- Fix: copy distinct rows into a temp table, truncate the hypertable,
-- reinsert.  This is the only reliable dedup approach for hypertables
-- without a surrogate primary key.
--
-- All four hypertables are cleaned:
--   health_metrics, sleep_stages, workout_heart_rate, workout_routes

BEGIN;

-- ============================================================
-- 1. health_metrics — non-nutrition rows
--    Uniqueness key: (metric_name, source, time, user_id)
-- ============================================================
CREATE TEMP TABLE _hm_clean_non_nutrition ON COMMIT DROP AS
SELECT DISTINCT ON (metric_name, source, time, user_id)
       time, user_id, metric_name, source, units, qty,
       min_val, avg_val, max_val, systolic, diastolic, source_uuid
FROM health_metrics
WHERE metric_name NOT LIKE 'dietary_%'
ORDER BY metric_name, source, time, user_id, source_uuid NULLS LAST;

-- ============================================================
-- 2. health_metrics — nutrition rows
--    Uniqueness key: (metric_name, source, time, user_id, qty)
-- ============================================================
CREATE TEMP TABLE _hm_clean_nutrition ON COMMIT DROP AS
SELECT DISTINCT ON (metric_name, source, time, user_id, qty)
       time, user_id, metric_name, source, units, qty,
       min_val, avg_val, max_val, systolic, diastolic, source_uuid
FROM health_metrics
WHERE metric_name LIKE 'dietary_%'
ORDER BY metric_name, source, time, user_id, qty, source_uuid NULLS LAST;

-- ============================================================
-- 3. sleep_stages
--    Uniqueness key: (start_time, end_time, stage, user_id)
-- ============================================================
CREATE TEMP TABLE _ss_clean ON COMMIT DROP AS
SELECT DISTINCT ON (start_time, end_time, stage, user_id)
       start_time, end_time, user_id, stage, duration_hr, source
FROM sleep_stages
ORDER BY start_time, end_time, stage, user_id;

-- ============================================================
-- 4. workout_heart_rate
--    Uniqueness key: (time, workout_id, user_id)
-- ============================================================
CREATE TEMP TABLE _whr_clean ON COMMIT DROP AS
SELECT DISTINCT ON (time, workout_id, user_id)
       time, workout_id, user_id, min_bpm, avg_bpm, max_bpm, source
FROM workout_heart_rate
ORDER BY time, workout_id, user_id;

-- ============================================================
-- 5. workout_routes
--    Uniqueness key: (time, workout_id, user_id)
-- ============================================================
CREATE TEMP TABLE _wr_clean ON COMMIT DROP AS
SELECT DISTINCT ON (time, workout_id, user_id)
       time, workout_id, user_id, latitude, longitude, altitude,
       speed, course, horizontal_accuracy, vertical_accuracy
FROM workout_routes
ORDER BY time, workout_id, user_id;

-- ============================================================
-- Truncate and reinsert — one table at a time.
-- CASCADE is not needed; these hypertables have no dependents.
-- ============================================================

-- workout_routes
TRUNCATE workout_routes;
INSERT INTO workout_routes
SELECT * FROM _wr_clean;

-- workout_heart_rate
TRUNCATE workout_heart_rate;
INSERT INTO workout_heart_rate
SELECT * FROM _whr_clean;

-- sleep_stages
TRUNCATE sleep_stages;
INSERT INTO sleep_stages
SELECT * FROM _ss_clean;

-- health_metrics (both halves go back into the same table)
TRUNCATE health_metrics;
INSERT INTO health_metrics
SELECT * FROM _hm_clean_non_nutrition;
INSERT INTO health_metrics
SELECT * FROM _hm_clean_nutrition;

COMMIT;

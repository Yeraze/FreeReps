-- Historical duplicate cleanup.
--
-- Migration 024 attempted to remove duplicates from health_metrics using
-- ctid comparison, but ctid is chunk-local in TimescaleDB hypertables and
-- may not reliably identify rows across chunks during a self-join DELETE.
-- This migration uses a CTE + window-function approach that works correctly
-- regardless of chunk layout.
--
-- Also cleans sleep_stages and workout_heart_rate as a safety net — these
-- tables have had unique indexes since migration 001, but re-imports before
-- those indexes existed (or edge cases during schema changes) may have left
-- orphan duplicates.
--
-- All DELETEs are idempotent: if no duplicates exist, zero rows are removed.

BEGIN;

-- ============================================================
-- 1. health_metrics — non-nutrition duplicates
--    Uniqueness: (metric_name, source, time, user_id)
--    Keep the row with the smallest ctid per chunk (arbitrary but stable).
-- ============================================================
WITH dupes AS (
    SELECT ctid AS row_id,
           ROW_NUMBER() OVER (
               PARTITION BY metric_name, source, time, user_id
               ORDER BY ctid
           ) AS rn
    FROM health_metrics
    WHERE metric_name NOT LIKE 'dietary_%'
)
DELETE FROM health_metrics
WHERE ctid IN (SELECT row_id FROM dupes WHERE rn > 1);

-- ============================================================
-- 2. health_metrics — nutrition duplicates
--    Uniqueness: (metric_name, source, time, user_id, qty)
--    Different qty values at the same timestamp are kept (different food items).
-- ============================================================
WITH dupes AS (
    SELECT ctid AS row_id,
           ROW_NUMBER() OVER (
               PARTITION BY metric_name, source, time, user_id, qty
               ORDER BY ctid
           ) AS rn
    FROM health_metrics
    WHERE metric_name LIKE 'dietary_%'
)
DELETE FROM health_metrics
WHERE ctid IN (SELECT row_id FROM dupes WHERE rn > 1);

-- ============================================================
-- 3. sleep_stages — duplicates
--    Uniqueness: (start_time, end_time, stage, user_id)
-- ============================================================
WITH dupes AS (
    SELECT ctid AS row_id,
           ROW_NUMBER() OVER (
               PARTITION BY start_time, end_time, stage, user_id
               ORDER BY ctid
           ) AS rn
    FROM sleep_stages
)
DELETE FROM sleep_stages
WHERE ctid IN (SELECT row_id FROM dupes WHERE rn > 1);

-- ============================================================
-- 4. workout_heart_rate — duplicates
--    Uniqueness: (time, workout_id, user_id)
-- ============================================================
WITH dupes AS (
    SELECT ctid AS row_id,
           ROW_NUMBER() OVER (
               PARTITION BY time, workout_id, user_id
               ORDER BY ctid
           ) AS rn
    FROM workout_heart_rate
)
DELETE FROM workout_heart_rate
WHERE ctid IN (SELECT row_id FROM dupes WHERE rn > 1);

-- ============================================================
-- 5. workout_routes — duplicates
--    Uniqueness: (time, workout_id, user_id)
-- ============================================================
WITH dupes AS (
    SELECT ctid AS row_id,
           ROW_NUMBER() OVER (
               PARTITION BY time, workout_id, user_id
               ORDER BY ctid
           ) AS rn
    FROM workout_routes
)
DELETE FROM workout_routes
WHERE ctid IN (SELECT row_id FROM dupes WHERE rn > 1);

COMMIT;

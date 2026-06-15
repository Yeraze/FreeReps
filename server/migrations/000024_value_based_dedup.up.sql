-- Fix: value-based dedup for HAE re-uploads.
--
-- Migration 023 split the original dedup index into three partial indexes,
-- but the non-nutrition and nutrition indexes had "WHERE source_uuid IS NULL"
-- filters. When HAE re-syncs, data points may carry a source_uuid that
-- changes between exports (or the same source_uuid with a re-assigned value).
-- Rows WITH source_uuid only matched idx_health_metrics_dedup_uuid
-- (user_id, source_uuid, time) — so if the UUID differed, duplicates
-- slipped through with no other index catching them.
--
-- Fix: drop the "source_uuid IS NULL" filter from the non-nutrition and
-- nutrition indexes so they cover ALL rows. This ensures that identical
-- (metric_name, source, time, user_id) tuples — or
-- (metric_name, source, time, user_id, qty) for nutrition — are always
-- deduplicated, regardless of source_uuid presence.
--
-- Before creating the wider indexes we must remove any existing duplicate
-- rows that would violate the new uniqueness constraints.

-- Step 1: Remove non-nutrition duplicates on (metric_name, source, time, user_id).
-- Keep the row with the smallest ctid (first physical insertion).
DELETE FROM health_metrics a
USING health_metrics b
WHERE a.metric_name NOT LIKE 'dietary_%'
  AND a.metric_name = b.metric_name
  AND a.source      = b.source
  AND a.time        = b.time
  AND a.user_id     = b.user_id
  AND a.ctid        > b.ctid;

-- Step 2: Remove nutrition duplicates on (metric_name, source, time, user_id, qty).
DELETE FROM health_metrics a
USING health_metrics b
WHERE a.metric_name LIKE 'dietary_%'
  AND a.metric_name = b.metric_name
  AND a.source      = b.source
  AND a.time        = b.time
  AND a.user_id     = b.user_id
  AND a.qty         = b.qty
  AND a.ctid        > b.ctid;

-- Step 3: Drop the old partial indexes.
DROP INDEX IF EXISTS idx_health_metrics_dedup_no_uuid;
DROP INDEX IF EXISTS idx_health_metrics_dedup_nutrition;

-- Step 4: Recreate without the source_uuid IS NULL filter.
-- Non-nutrition: same metric + source + time + user = duplicate (skip).
CREATE UNIQUE INDEX idx_health_metrics_dedup_no_uuid
    ON health_metrics (metric_name, source, time, user_id)
    WHERE metric_name NOT LIKE 'dietary_%';

-- Nutrition: same metric + source + time + user + qty = duplicate (skip).
-- Different qty at the same timestamp is kept (e.g. multiple food items from
-- Cronometer all synced to midnight).
CREATE UNIQUE INDEX idx_health_metrics_dedup_nutrition
    ON health_metrics (metric_name, source, time, user_id, qty)
    WHERE metric_name LIKE 'dietary_%';

-- Keep idx_health_metrics_dedup_uuid unchanged — it still provides fast
-- dedup when the same Apple Health sample UUID is re-imported.

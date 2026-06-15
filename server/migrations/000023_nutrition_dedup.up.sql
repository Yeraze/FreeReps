-- Fix #3: Nutrition metrics with identical timestamps are deduplicated.
--
-- The original unique index (metric_name, source, time, user_id) causes
-- ON CONFLICT DO NOTHING to drop nutrition samples that share a timestamp.
-- Cronometer syncs all daily entries to Apple Health at 12:00 AM, so only
-- one sample per metric survives.
--
-- Replace with three partial indexes:
--   1. UUID-based dedup for rows WITH source_uuid (FreeReps iOS app samples)
--   2. Standard timestamp dedup for non-nutrition rows WITHOUT source_uuid
--   3. Nutrition dedup includes qty — allows different food items at the same
--      timestamp while still preventing exact-value duplicate re-imports

DROP INDEX IF EXISTS idx_health_metrics_dedup;

CREATE UNIQUE INDEX idx_health_metrics_dedup_uuid
    ON health_metrics (user_id, source_uuid, time)
    WHERE source_uuid IS NOT NULL;

CREATE UNIQUE INDEX idx_health_metrics_dedup_no_uuid
    ON health_metrics (metric_name, source, time, user_id)
    WHERE source_uuid IS NULL AND metric_name NOT LIKE 'dietary_%';

CREATE UNIQUE INDEX idx_health_metrics_dedup_nutrition
    ON health_metrics (metric_name, source, time, user_id, qty)
    WHERE source_uuid IS NULL AND metric_name LIKE 'dietary_%';

-- Nutrition display metadata and cumulative flags.
UPDATE metric_allowlist SET display_label = 'Calories',    display_unit = 'kcal', is_cumulative = true WHERE metric_name = 'dietary_energy_consumed';
UPDATE metric_allowlist SET display_label = 'Protein',     display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_protein';
UPDATE metric_allowlist SET display_label = 'Carbs',       display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_carbohydrates';
UPDATE metric_allowlist SET display_label = 'Total Fat',   display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_fat_total';
UPDATE metric_allowlist SET display_label = 'Fiber',       display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_fiber';
UPDATE metric_allowlist SET display_label = 'Sugar',       display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_sugar';
UPDATE metric_allowlist SET display_label = 'Sodium',      display_unit = 'mg',   is_cumulative = true WHERE metric_name = 'dietary_sodium';
UPDATE metric_allowlist SET display_label = 'Cholesterol',  display_unit = 'mg',  is_cumulative = true WHERE metric_name = 'dietary_cholesterol';
UPDATE metric_allowlist SET display_label = 'Sat. Fat',    display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_fat_saturated';
UPDATE metric_allowlist SET display_label = 'Mono. Fat',   display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_fat_monounsaturated';
UPDATE metric_allowlist SET display_label = 'Poly. Fat',   display_unit = 'g',    is_cumulative = true WHERE metric_name = 'dietary_fat_polyunsaturated';
UPDATE metric_allowlist SET display_label = 'Caffeine',    display_unit = 'mg',   is_cumulative = true WHERE metric_name = 'dietary_caffeine';
UPDATE metric_allowlist SET display_label = 'Water',       display_unit = 'L',    is_cumulative = true WHERE metric_name = 'dietary_water';
UPDATE metric_allowlist SET display_label = 'Calcium',     display_unit = 'mg',   is_cumulative = true WHERE metric_name = 'dietary_calcium';
UPDATE metric_allowlist SET display_label = 'Iron',        display_unit = 'mg',   is_cumulative = true WHERE metric_name = 'dietary_iron';
UPDATE metric_allowlist SET display_label = 'Potassium',   display_unit = 'mg',   is_cumulative = true WHERE metric_name = 'dietary_potassium';
UPDATE metric_allowlist SET display_label = 'Vitamin C',   display_unit = 'mg',   is_cumulative = true WHERE metric_name = 'dietary_vitamin_c';
UPDATE metric_allowlist SET display_label = 'Vitamin D',   display_unit = 'mcg',  is_cumulative = true WHERE metric_name = 'dietary_vitamin_d';

-- Fix blood_oxygen_saturation data from non-Oura sources (e.g. Apple Health, demo) that was
-- incorrectly stored as a percentage (e.g. 96.5) instead of a fraction (e.g. 0.965).
-- The display_multiplier=100 was added expecting fraction storage. This migration normalizes
-- any remaining percentage-range values (>1) from non-Oura sources.
UPDATE health_metrics
SET qty = qty / 100
WHERE metric_name = 'blood_oxygen_saturation'
  AND source != 'Oura'
  AND qty > 1;

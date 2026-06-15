-- Revert to the source_uuid IS NULL partial indexes from migration 023.
DROP INDEX IF EXISTS idx_health_metrics_dedup_no_uuid;
DROP INDEX IF EXISTS idx_health_metrics_dedup_nutrition;

CREATE UNIQUE INDEX idx_health_metrics_dedup_no_uuid
    ON health_metrics (metric_name, source, time, user_id)
    WHERE source_uuid IS NULL AND metric_name NOT LIKE 'dietary_%';

CREATE UNIQUE INDEX idx_health_metrics_dedup_nutrition
    ON health_metrics (metric_name, source, time, user_id, qty)
    WHERE source_uuid IS NULL AND metric_name LIKE 'dietary_%';

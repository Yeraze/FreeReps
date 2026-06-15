DROP INDEX IF EXISTS idx_health_metrics_dedup_uuid;
DROP INDEX IF EXISTS idx_health_metrics_dedup_no_uuid;
DROP INDEX IF EXISTS idx_health_metrics_dedup_nutrition;

CREATE UNIQUE INDEX idx_health_metrics_dedup
    ON health_metrics (metric_name, source, time, user_id);

UPDATE metric_allowlist SET display_label = '', display_unit = '', is_cumulative = false
WHERE metric_name LIKE 'dietary_%';

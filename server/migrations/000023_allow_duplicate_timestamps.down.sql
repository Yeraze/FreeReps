-- Revert to the original unique index without source_uuid.
DROP INDEX IF EXISTS idx_health_metrics_dedup;

CREATE UNIQUE INDEX idx_health_metrics_dedup
    ON health_metrics (metric_name, source, time, user_id);

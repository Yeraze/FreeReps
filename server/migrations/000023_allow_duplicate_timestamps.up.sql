-- Allow multiple health metric samples at the same (metric, source, time, user)
-- by including source_uuid in the unique index. Each sample from Apple Health /
-- HAE carries a distinct source_uuid, so nutrition entries (e.g. multiple
-- dietary_protein records at the same meal timestamp) are no longer silently
-- dropped by ON CONFLICT DO NOTHING.
--
-- PostgreSQL treats NULLs as distinct in unique indexes, so rows without a
-- source_uuid are never constrained by this index (same as before for legacy
-- data without UUIDs).

DROP INDEX IF EXISTS idx_health_metrics_dedup;

CREATE UNIQUE INDEX idx_health_metrics_dedup
    ON health_metrics (metric_name, source, time, user_id, source_uuid);

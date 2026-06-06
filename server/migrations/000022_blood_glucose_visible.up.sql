-- Make blood_glucose visible for all existing users who already have data.
-- The defaultVisibleMetrics Go map only applies when there is NO override row,
-- so users with prior saved-settings pages would never see the new metric unless
-- we explicitly insert a visibility row here.
INSERT INTO user_metric_visibility (user_id, metric_name, visible)
SELECT DISTINCT h.user_id, 'blood_glucose', true
FROM health_metrics h
WHERE h.metric_name = 'blood_glucose'
ON CONFLICT (user_id, metric_name) DO UPDATE SET visible = true;

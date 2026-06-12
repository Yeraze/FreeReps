-- Add display metadata for blood glucose metric.
UPDATE metric_allowlist SET display_label = 'Blood Glucose', display_unit = 'mg/dL' WHERE metric_name = 'blood_glucose';

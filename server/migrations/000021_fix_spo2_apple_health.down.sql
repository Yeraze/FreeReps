UPDATE health_metrics
SET qty = qty * 100
WHERE metric_name = 'blood_oxygen_saturation'
  AND source != 'Oura'
  AND qty <= 1;

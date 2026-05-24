package storage

import (
	"strings"
	"testing"
)

// TestSourcePriorityCaseSQL verifies that the SQL CASE expression correctly
// maps source names to priority numbers, ensuring higher-priority sources
// win during deduplication.
func TestSourcePriorityCaseSQL(t *testing.T) {
	tests := []struct {
		name       string
		priorities []string
		wantSQL    string
	}{
		{
			name:       "empty priorities returns constant 1 (no-op dedup)",
			priorities: nil,
			wantSQL:    "1",
		},
		{
			name:       "single named source",
			priorities: []string{"Oura"},
			wantSQL:    "CASE WHEN source LIKE 'Oura%' THEN 1 ELSE 2 END",
		},
		{
			name:       "oura then empty string",
			priorities: []string{"Oura", ""},
			wantSQL:    "CASE WHEN source LIKE 'Oura%' THEN 1 WHEN source = '' THEN 2 ELSE 3 END",
		},
		{
			name:       "three sources with prefix matching",
			priorities: []string{"Oura", "Apple Watch", ""},
			wantSQL:    "CASE WHEN source LIKE 'Oura%' THEN 1 WHEN source LIKE 'Apple Watch%' THEN 2 WHEN source = '' THEN 3 ELSE 4 END",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := sourcePriorityCaseSQL(tt.priorities)
			if got != tt.wantSQL {
				t.Errorf("sourcePriorityCaseSQL() =\n  %q\nwant:\n  %q", got, tt.wantSQL)
			}
		})
	}
}

// TestDedupCTE verifies that the generated CTE has the correct structure:
// a WITH clause using time_bucket, ROW_NUMBER, and the right parameter placeholders.
func TestDedupCTE(t *testing.T) {
	cte := dedupCTE([]string{"Oura", ""}, "$2", "$3", "$4", "$5")

	checks := []string{
		"WITH deduped AS",
		"time_bucket('5 minutes', time)",
		"ROW_NUMBER()",
		"LIKE 'Oura%' THEN 1",
		"source = '' THEN 2",
		"metric_name = $2",
		"time >= $3",
		"time < $4",
		"user_id = $5",
	}

	for _, check := range checks {
		if !strings.Contains(cte, check) {
			t.Errorf("dedupCTE missing %q in:\n%s", check, cte)
		}
	}
}

// TestBuildMetricStatsQueryCumulative verifies that GetMetricStats uses SUM
// for cumulative metrics (step_count, active_energy, distance_*, etc.) instead
// of AVG. HAE emits per-second rate samples for these, so AVG over a day
// returns the wrong value (e.g. ~0.6 instead of ~3215 for step_count).
func TestBuildMetricStatsQueryCumulative(t *testing.T) {
	cumulative := []string{
		"step_count",
		"active_energy",
		"basal_energy_burned",
		"apple_exercise_time",
		"apple_move_time",
		"apple_stand_time",
		"flights_climbed",
		"push_count",
		"swimming_stroke_count",
		"distance_walking_running",
		"distance_cycling",
		"distance_swimming",
		"distance_wheelchair",
		"distance_downhill_snow_sports",
	}
	for _, metric := range cumulative {
		t.Run(metric, func(t *testing.T) {
			sql := buildMetricStatsQuery(metric, nil)
			if !strings.Contains(sql, "SUM(COALESCE(qty, avg_val))") {
				t.Errorf("expected SUM aggregate for cumulative metric %q, got:\n%s", metric, sql)
			}
			if strings.Contains(sql, "AVG(COALESCE(qty, avg_val))") {
				t.Errorf("did not expect AVG aggregate for cumulative metric %q, got:\n%s", metric, sql)
			}
			// MIN/MAX/STDDEV/COUNT are still emitted unchanged.
			for _, want := range []string{
				"MIN(COALESCE(qty, min_val))",
				"MAX(COALESCE(qty, max_val))",
				"STDDEV_POP(COALESCE(qty, avg_val))",
				"COUNT(*)",
			} {
				if !strings.Contains(sql, want) {
					t.Errorf("expected %q in stats query for %q, got:\n%s", want, metric, sql)
				}
			}
		})
	}
}

// TestBuildMetricStatsQueryNonCumulative verifies that non-cumulative metrics
// (heart_rate, body_mass, etc.) still use AVG as before.
func TestBuildMetricStatsQueryNonCumulative(t *testing.T) {
	for _, metric := range []string{"heart_rate", "body_mass", "blood_pressure_systolic", "respiratory_rate"} {
		t.Run(metric, func(t *testing.T) {
			sql := buildMetricStatsQuery(metric, nil)
			if !strings.Contains(sql, "AVG(COALESCE(qty, avg_val))") {
				t.Errorf("expected AVG aggregate for non-cumulative metric %q, got:\n%s", metric, sql)
			}
			if strings.Contains(sql, "SUM(COALESCE(qty, avg_val))") {
				t.Errorf("did not expect SUM aggregate for non-cumulative metric %q, got:\n%s", metric, sql)
			}
		})
	}
}

// TestDedupCTEMultiMetric verifies the multi-metric CTE partitions by both
// metric_name and time bucket, preventing cross-metric deduplication.
func TestDedupCTEMultiMetric(t *testing.T) {
	cte := dedupCTEMultiMetric([]string{"Oura", ""}, "$1", "$2,$3")

	checks := []string{
		"WITH deduped AS",
		"PARTITION BY metric_name, time_bucket('5 minutes', time)",
		"user_id = $1",
		"metric_name IN ($2,$3)",
	}

	for _, check := range checks {
		if !strings.Contains(cte, check) {
			t.Errorf("dedupCTEMultiMetric missing %q in:\n%s", check, cte)
		}
	}
}

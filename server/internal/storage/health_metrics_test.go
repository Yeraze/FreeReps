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
	cte := dedupCTE([]string{"Oura", ""}, "$2", "$3", "$4", "$5", false)

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

// TestNutritionMetricsCumulative verifies that dietary_* metrics are recognized
// as cumulative, so they use SUM and skip the 5-minute dedup.
func TestNutritionMetricsCumulative(t *testing.T) {
	for _, metric := range []string{"dietary_protein", "dietary_fiber", "dietary_carbohydrates", "dietary_fat_total", "dietary_energy_consumed"} {
		t.Run(metric, func(t *testing.T) {
			if !isCumulative(metric) {
				t.Errorf("expected %q to be cumulative", metric)
			}
			sql := buildMetricStatsQuery(metric, nil)
			if !strings.Contains(sql, "SUM(COALESCE(qty, avg_val))") {
				t.Errorf("expected SUM aggregate for nutrition metric %q, got:\n%s", metric, sql)
			}
			if !strings.Contains(sql, "1 AS rn") {
				t.Errorf("expected '1 AS rn' (no dedup) for nutrition metric %q, got:\n%s", metric, sql)
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

// TestBuildMetricStatsQueryCumulativeSkipsDedup verifies that for cumulative
// metrics the generated stats query does NOT include the ROW_NUMBER-based
// 5-minute dedup. HAE emits ~11K per-second rate samples for step_count in a
// single day; filtering by ROW_NUMBER()=1 across 5-minute buckets would drop
// ~99% of them and collapse the daily total to ~1% of reality. The 5-minute
// dedup exists to break ties between competing sources (Oura/Apple/HAE) on
// the same wrist-moment, not to thin out high-frequency single-source streams.
func TestBuildMetricStatsQueryCumulativeSkipsDedup(t *testing.T) {
	for _, metric := range []string{"step_count", "active_energy", "distance_walking_running", "flights_climbed"} {
		t.Run(metric, func(t *testing.T) {
			sql := buildMetricStatsQuery(metric, []string{"Oura", ""})
			if strings.Contains(sql, "ROW_NUMBER()") {
				t.Errorf("expected no ROW_NUMBER() dedup for cumulative metric %q, got:\n%s", metric, sql)
			}
			if strings.Contains(sql, "PARTITION BY time_bucket") {
				t.Errorf("expected no time_bucket partition for cumulative metric %q, got:\n%s", metric, sql)
			}
			// CTE should still be present and emit a constant rn so the
			// caller's WHERE rn = 1 predicate is a no-op.
			if !strings.Contains(sql, "1 AS rn") {
				t.Errorf("expected '1 AS rn' constant in CTE for cumulative metric %q, got:\n%s", metric, sql)
			}
		})
	}
}

// TestBuildMetricStatsQueryNonCumulativeKeepsDedup verifies that non-cumulative
// metrics still get the 5-minute ROW_NUMBER dedup, which is needed when more
// than one source reports the same wrist-moment (e.g. Oura vs Apple Watch
// heart rate).
func TestBuildMetricStatsQueryNonCumulativeKeepsDedup(t *testing.T) {
	for _, metric := range []string{"heart_rate", "body_mass", "respiratory_rate", "blood_pressure_systolic"} {
		t.Run(metric, func(t *testing.T) {
			sql := buildMetricStatsQuery(metric, []string{"Oura", ""})
			if !strings.Contains(sql, "ROW_NUMBER()") {
				t.Errorf("expected ROW_NUMBER() dedup for non-cumulative metric %q, got:\n%s", metric, sql)
			}
			if !strings.Contains(sql, "PARTITION BY time_bucket('5 minutes', time)") {
				t.Errorf("expected 5-minute time_bucket partition for non-cumulative metric %q, got:\n%s", metric, sql)
			}
		})
	}
}

// TestDedupCTECumulativeFlag verifies the isCumulative flag swaps the CTE
// body between the ROW_NUMBER form (false) and the constant-rn form (true).
func TestDedupCTECumulativeFlag(t *testing.T) {
	cumulativeCTE := dedupCTE([]string{"Oura", ""}, "$2", "$3", "$4", "$5", true)
	if strings.Contains(cumulativeCTE, "ROW_NUMBER()") {
		t.Errorf("isCumulative=true should not emit ROW_NUMBER, got:\n%s", cumulativeCTE)
	}
	if !strings.Contains(cumulativeCTE, "1 AS rn") {
		t.Errorf("isCumulative=true should emit constant '1 AS rn', got:\n%s", cumulativeCTE)
	}

	normalCTE := dedupCTE([]string{"Oura", ""}, "$2", "$3", "$4", "$5", false)
	if !strings.Contains(normalCTE, "ROW_NUMBER()") {
		t.Errorf("isCumulative=false should emit ROW_NUMBER, got:\n%s", normalCTE)
	}
}

// TestDedupCTEMultiMetric verifies the multi-metric CTE emits a constant rn=1
// (no dedup), since all callers pass only cumulative metrics which should
// retain every row.
func TestDedupCTEMultiMetric(t *testing.T) {
	cte := dedupCTEMultiMetric([]string{"Oura", ""}, "$1", "$2,$3")

	checks := []string{
		"WITH deduped AS",
		"1 AS rn",
		"user_id = $1",
		"metric_name IN ($2,$3)",
	}

	for _, check := range checks {
		if !strings.Contains(cte, check) {
			t.Errorf("dedupCTEMultiMetric missing %q in:\n%s", check, cte)
		}
	}

	if strings.Contains(cte, "ROW_NUMBER()") {
		t.Errorf("dedupCTEMultiMetric should not emit ROW_NUMBER for cumulative metrics, got:\n%s", cte)
	}
}

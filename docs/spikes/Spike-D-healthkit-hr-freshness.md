# Spike D: HealthKit Heart Rate Freshness

## Goal

Measure whether HealthKit heart-rate samples are fresh enough to be useful as an optional confidence boost.

## Matrix

| Scenario | hrAgeSec p50 | p90 | p95 | Baseline confidence | Participates in scoring |
| --- | --- | --- | --- | --- | --- |
| Normal sleep | Not tested | Not tested | Not tested | Not tested | Not tested |
| Before ring time | Not tested | Not tested | Not tested | Not tested | Not tested |
| After alarm starts | Not tested | Not tested | Not tested | Not tested | Not tested |
| HealthKit denied | N/A | N/A | N/A | none | No |

## Exit Criteria

Heart rate participates only when `hrAgeSec <= 120` and baseline confidence is at least medium.


# Spike C: Motion Awake Candidate

## Goal

Collect motion windows and verify that motion-first scoring identifies high-confidence awake candidates without allowing single spikes or stale sensors to silence alarms.

## Matrix

| Action | Expected trigger | Actual score | Reason codes | Misclassified | Raw window JSON |
| --- | --- | --- | --- | --- | --- |
| Wake and sit up | Yes | Not tested | Not tested | Not tested | Pending |
| Roll over once | No | Not tested | Not tested | Not tested | Pending |
| Grab phone | Maybe | Not tested | Not tested | Not tested | Pending |
| Motion stale | No | Not tested | `motionStale` expected | Not tested | Pending |
| HR-only spike | No | Not tested | `heartRateOnlyRejected` expected | Not tested | Pending |

## Exit Criteria

Every auto-silence decision has score, confidence, reason codes, and sensor freshness in logs.


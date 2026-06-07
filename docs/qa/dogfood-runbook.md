# Dogfood Runbook

## Entry Criteria

- iPhone can create, disable, and delete local alarms.
- Watch can receive or simulate alarm config and complete arming.
- Smart Mode never shows Ready before Watch arming and runtime scheduling.
- Each AlarmRun can export JSONL logs.
- Feature flags keep auto silence, re-sleep detection, and gesture snooze conservative.

## Manual Procedure

1. Create a Smart Mode alarm on iPhone.
2. Confirm the Watch shows Needs Arming.
3. Arm on Watch and record whether runtime scheduling succeeds.
4. Let the alarm reach ring time.
5. Stop or snooze from Watch.
6. Export logs from iPhone.
7. Label the run outcome: woke up, false silence, false re-alarm, missed alarm, not wearing Watch, or manual stop.

## v0.2 Targets

- 100 internal dogfood alarms.
- `missedAlarm` count must be 0.
- False silence target below 3-5%.
- False re-alarm target below 10-15%.
- Motion stale or Watch not worn must produce 0 false silences.

## Feature Flags

v0.2 default flags:

- `autoSilenceEnabled = false`
- `reSleepDetectionEnabled = false`
- `gestureSnoozeEnabled = true`
- `heartRateBoostEnabled = true`
- `maxReAlarmCount = 2`

Auto silence and re-sleep detection can only be enabled for named internal test runs with exported logs.

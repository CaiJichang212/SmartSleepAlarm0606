# Dogfood Runbook

## Entry Criteria

- iPhone can create, disable, and delete local alarms.
- Watch 能接收或模拟闹铃配置，并完成启用确认。
- Smart Mode 在 Watch 完成启用确认且 runtime session 成功预约前，绝不显示 Ready。
- Each AlarmRun can export JSONL logs.
- Feature flags keep auto silence, re-sleep detection, and gesture snooze conservative.

## Manual Procedure

1. Create a Smart Mode alarm on iPhone.
2. 确认 Watch 显示“等待 Watch 确认”。
3. 在 Watch 上启用本次闹铃，并记录 runtime session 是否预约成功。
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

## v0.2 Device Integration Gate

Before a dogfood run is counted as valid:

- iPhone and Apple Watch are paired to the same Apple ID.
- iPhone app has notification authorization.
- Watch app 在启用确认前显示已收到的闹铃配置。
- Watch 在无配置时启用确认失败，并记录为 `missing_alarm_config`。
- iPhone fallback channel is recorded as `iOSLocalNotification`.
- Exported JSONL contains at least one state transition and one channel event for the run.
- Runtime-session result is recorded as success or `runtime_session_not_scheduled`.

# Device Test Matrix

| Area | Scenario | Expected result | Simulator | Real device |
| --- | --- | --- | --- | --- |
| Smart Mode status | Watch 未完成启用确认 | iPhone 显示“需在 Watch 上启用” | Covered by core test | Pending |
| Smart Mode status | Runtime scheduled | iPhone and Watch show Ready | Covered by core test | Pending |
| Motion freshness | Motion stale | Auto silence and gesture snooze disabled | Covered by core test | Pending |
| Heart rate | HR-only spike | Does not auto silence | Covered by core test | Pending |
| Gesture snooze | Valid double rotation while ringing | Enters SNOOZED | Covered by core test | Pending |
| Alarm channel | Watch/iPhone disconnected | Both execute preconfigured channels | Not available | Pending |
| Runtime session | Watch locked before alarm | Logs scheduling and start result | Not available | Pending |
| Connectivity | iPhone sends alarm config | Watch receives config and can complete enable confirmation | Requires paired real devices | Not tested |
| Connectivity | Watch sends enable-confirmation result | iPhone status updates to Ready or Fallback | Requires paired real devices | Not tested |
| Connectivity | Watch sends session result and run summary | iPhone card keeps arming status, debug area only shows latest summary | Simulator plus paired real devices | Not tested |
| Runtime | Watch schedules runtime session | Runtime log records scheduled target start | Requires paired real devices | Not tested |
| Preflight | Watch battery low or motion unavailable before arming | Watch fails closed, iPhone keeps fallback visible, session summary is exported | Partial via simulator and fakes | Pending |
| Experimental auto silence | HR-only spike | Candidate is rejected and ringing continues | Covered by watch tests | Pending |
| Experimental auto silence | Motion stale during candidate | Candidate is rejected and ringing continues | Covered by watch tests | Pending |
| Experimental auto silence | Confirmation window met | State reaches `SILENCED_MONITORING` and logs `auto_silenced` | Covered by watch tests | Pending |
| Experimental re-sleep | False re-alarm / max re-alarm count | Risk log present and re-ring count stays bounded | Covered by watch tests plus real-device follow-up | Pending |
| Fallback | iPhone fallback notification scheduled | `AlarmChannelLog` records `iOSLocalNotification` | Simulator plus JSONL inspection | Not tested |
| Notification | iPhone fallback fires under Silent Mode and Sleep Focus | User notices fallback alarm | Requires paired real devices | Not tested |
| Ringer | Watch haptic feedback starts, snoozes, and stops | User can perceive haptic pattern on wrist | Requires paired real devices | Not tested |
| Export | AlarmRun JSONL export | Export contains state and channel events | Core test plus Simulator inspection | Not tested |

## AlarmKit Manual Device Note

AlarmKit is compile-gated in the current iOS build slice. Before enabling it as the default fallback on iOS 26+, verify on a real iPhone that:

- `NSAlarmKitUsageDescription` is present and user-readable.
- `AlarmManager.requestAuthorization()` returns `.authorized` after consent.
- A one-time alarm scheduled through `AlarmManager.schedule(id:configuration:)` alerts at the expected wall-clock time.
- Stop and snooze actions are reflected in `AlarmChannelLog`.
- If AlarmKit authorization is denied, `BackupChannelPolicy` routes to `iOSLocalNotification` or `manualFallbackPrompt`.

## Runtime Session Manual Device Note

Simulator cannot prove `WKExtendedRuntimeSession.start(at:)` timing accuracy. On a real Apple Watch, verify that:

- Runtime start occurs close to the planned pre-monitor target.
- `RuntimeSessionLog.actualStartAt` is written when the session starts.
- Long lead-time alarms do not create a ring timer until runtime actually starts.
- Runtime invalidation before alarm time downgrades to `fallbackPhoneAlarm`.

## CoreMotion Manual Device Note

Simulator tests only verify sampler wiring. On a real Apple Watch, verify that:

- Device motion starts during `PRE_MONITORING`.
- `SensorFreshness.motionSampleCount` increases at least once per second.
- `motionLastSampleAgeSec > 2` is emitted by the stale tick and disables auto silence and gesture snooze without overwriting `completed`, `snoozed`, or `fallbackPhoneAlarm`.
- Left wrist and right wrist produce usable rotation samples.
- `SensorSummary` is exported at roughly 3-second windows and can be replayed with `gyroPeak`, `postureDelta`, and `motionContinuitySec`.
- No HealthKit heart-rate sample is required for motion-only Smart Mode.

## HealthKit Manual Device Note

Simulator tests only cover the conservative mapper and query wiring. On a real Apple Watch, verify that:

- Heart-rate authorization denied does not block Smart Mode arming.
- A recent heart-rate sample maps to `SensorFreshness.hrLastSampleAgeSec <= 120`.
- Missing or stale heart-rate data keeps `heartRateUsable == false` while motion freshness remains usable.

## P0 Reliability Chain Required Results

| Scenario | Required result | Required log |
| --- | --- | --- |
| Watch armed and session scheduled | iPhone shows Ready | `armingResult` and `RuntimeSessionLog` |
| Watch session invalidated | iPhone shows Fallback Only | `RuntimeSessionLog.invalidationReason` |
| AlarmKit unavailable | Local Notification or manual prompt shown | `AlarmChannelLog.channel` |
| Notification denied | Manual fallback prompt shown | `authorizationState: denied` |
| Runtime starts before alarm | Watch enters PRE_MONITORING | `preMonitorActualStartAt` or runtime actual start |
| Motion stale | Auto silence and gesture disabled | `SensorFreshness.motionLastSampleAgeSec` |
| User reports false silence | Outcome exported | `OutcomeLabel.falseSilenceReported` |

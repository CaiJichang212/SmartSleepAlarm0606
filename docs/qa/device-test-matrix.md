# Device Test Matrix

| Area | Scenario | Expected result | Simulator | Real device |
| --- | --- | --- | --- | --- |
| Smart Mode status | Watch not armed | iPhone shows Needs Watch Arming | Covered by core test | Pending |
| Smart Mode status | Runtime scheduled | iPhone and Watch show Ready | Covered by core test | Pending |
| Motion freshness | Motion stale | Auto silence and gesture snooze disabled | Covered by core test | Pending |
| Heart rate | HR-only spike | Does not auto silence | Covered by core test | Pending |
| Gesture snooze | Valid double rotation while ringing | Enters SNOOZED | Covered by core test | Pending |
| Alarm channel | Watch/iPhone disconnected | Both execute preconfigured channels | Not available | Pending |
| Runtime session | Watch locked before alarm | Logs scheduling and start result | Not available | Pending |
| Connectivity | iPhone sends alarm config | Watch receives config and can arm | Requires paired real devices | Not tested |
| Connectivity | Watch sends arming result | iPhone status updates to Ready or Fallback | Requires paired real devices | Not tested |
| Runtime | Watch schedules runtime session | Runtime log records scheduled target start | Requires paired real devices | Not tested |
| Fallback | iPhone fallback notification scheduled | `AlarmChannelLog` records `iOSLocalNotification` | Simulator plus JSONL inspection | Not tested |
| Notification | iPhone fallback fires under Silent Mode and Sleep Focus | User notices fallback alarm | Requires paired real devices | Not tested |
| Ringer | Watch haptic feedback starts, snoozes, and stops | User can perceive haptic pattern on wrist | Requires paired real devices | Not tested |
| Export | AlarmRun JSONL export | Export contains state and channel events | Core test plus Simulator inspection | Not tested |

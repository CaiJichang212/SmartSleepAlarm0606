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


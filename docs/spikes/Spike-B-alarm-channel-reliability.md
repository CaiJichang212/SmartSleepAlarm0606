# Spike B: Alarm Channel Reliability

## Goal

Verify Watch haptic/audio, iOS AlarmKit, local notifications, foreground audio, and manual fallback prompt behavior across real device modes.

## Matrix

| Scenario | watchRuntimeHapticAudio | iOSAlarmKit | iOSLocalNotification | foregroundAudio | manualFallbackPrompt | Strategy |
| --- | --- | --- | --- | --- | --- | --- |
| Silent Mode | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| Sleep Focus | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| Do Not Disturb | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| App backgrounded | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| App terminated | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |

## Exit Criteria

v0.2 dogfood cannot start until a default fallback strategy is selected and missed-alarm risk is documented.

## Notification Fallback Implementation

v0.2 uses `UNNotificationSound.default` for the iPhone fallback notification. Critical-alert behavior is not a default v0.2 path because it depends on entitlement approval, explicit authorization, Apple review, and product policy.

`Apps/iOS/Sources/BackupAlarmScheduler.swift` records an `AlarmChannelLog` every time the fallback notification is scheduled. Simulator builds prove compile-time API usage and local log visibility only. Real-device rows remain required for Silent Mode, Sleep Focus, locked screen, app terminated, low battery, and disconnected Watch.

## Watch Ringer Adapter

The Watch haptic adapter is `Apps/Watch/Sources/WatchAlarmRinger.swift`.
Simulator build verifies compile-time API usage only. Real-device rows are required for haptic strength, audible behavior, Silent Mode, Sleep Focus, locked screen, and app background state.

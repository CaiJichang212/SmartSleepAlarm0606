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


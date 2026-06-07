# Spike A: Watch Runtime Session

## Goal

Verify whether Watch arming can schedule and start a runtime session early enough for pre-monitoring.

## Matrix

| Scenario | Scheduled | Actual start | Delay | Reached ring | Failure reason | iPhone fallback | Log complete | Decision |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Single alarm, 30 minutes out | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| Watch locked | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| Watch force quit | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| Low battery | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |
| Bluetooth disconnected | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Not tested | Requires device |

## Exit Criteria

Supported and downgraded scenarios are explicit, and each failure can be represented in runtime/session logs.


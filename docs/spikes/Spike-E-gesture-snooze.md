# Spike E: Gesture Snooze

## Goal

Tune the constrained Watch gesture so intentional double wrist rotation can snooze while common night motions are rejected.

## Matrix

| Action | Expected trigger | Actual confidence | Rotation peak | Direction consistency | Accepted | Raw window JSON |
| --- | --- | --- | --- | --- | --- | --- |
| Intentional double rotation | Yes | Not tested | Not tested | Not tested | Not tested | Pending |
| Roll over | No | Not tested | Not tested | Not tested | Not tested | Pending |
| Scratch wrist | No | Not tested | Not tested | Not tested | Not tested | Pending |
| Pick up phone | No | Not tested | Not tested | Not tested | Not tested | Pending |
| First 1.5s of ringing | No | Not tested | Not tested | Not tested | Not tested | Pending |

## Exit Criteria

Gesture snooze works only in `RINGING` or `RE_RINGING`, after cooldown, with fresh motion and direction-consistent rotations.


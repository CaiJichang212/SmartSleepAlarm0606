# SmartSleep Alarm v0.2 MVP

SmartSleep Alarm v0.2 is a spike-first iOS + watchOS MVP for validating an Apple Watch smart alarm chain.

The product rule is conservative: reliability beats intelligence. If the app is uncertain, the alarm keeps ringing and the iPhone fallback channel remains visible.

## Structure

```text
Apps/iOS/                  iPhone SwiftUI MVP shell
Apps/Watch/                Watch SwiftUI MVP shell
Packages/SmartSleepCore/   Pure Swift models, state machine, scoring, logging, payloads
docs/prd/                  v0.2 source-of-truth PRD
docs/adr/                  Engineering decisions
docs/spikes/               Device spike matrices
docs/qa/                   Dogfood and device testing
```

## Local Commands

```bash
xcodegen generate
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
  swift test --package-path Packages/SmartSleepCore
```

Use Xcode or XcodeBuildMCP to build the `SmartSleepAlarm` and `SmartSleepWatch` schemes for Simulator.

## Current Scope

- Pure Swift core models and state machine.
- Motion-first awake scoring with heart-rate-only rejection.
- Gesture snooze detector with ringing-state and cooldown constraints.
- Append-only JSONL event store.
- WatchConnectivity payload types and mock outbox behavior.
- iOS/watchOS SwiftUI shells for dogfood and spike work.

## Not Implemented Yet

Real AlarmKit, WatchConnectivity, WKExtendedRuntimeSession, CoreMotion, HealthKit, haptic/audio alarm channels, and device reliability matrices require Apple-device integration work and manual testing.


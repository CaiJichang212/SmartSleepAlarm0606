# Experimental Auto Silence and Re-Sleep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 feature flag 保护下接通自动静音和再睡检测真实链路，同时保持 v0.2 默认保守、不确定继续响铃。

**Architecture:** 只在 Watch runtime 已进入 ringing 后使用 `SensorSummary` + `SensorFreshness` 驱动实验逻辑，且每次决策前同一 runId 下必须已经记录 freshness 和 summary，保证误判可回放。自动静音必须两阶段：先 `AWAKE_CANDIDATE`，再经过可注入时间参数的确认窗口进入 `SILENCED_MONITORING`；candidate rejected 回到进入 candidate 前的状态。再睡检测只在 `SILENCED_MONITORING` 中运行，日志写风险原因，不写“已睡着”。

**Tech Stack:** Swift 6.1, XCTest, SmartSleepCore scorers, WatchAlarmRunEngine, JSONL logs, XcodeBuildMCP.

---

## Preconditions

- `watch-ios-connectivity-run-summary` 已完成。
- `watch-sensor-preflight` 已完成。
- `WatchAlarmRunLogging` 已有 `recordSummary(_:)`、`eventCount(runId:)`。
- `WatchAppModel` 已能收到并记录 sensor summary。
- fake logger 已把 `summaryLogs` 纳入 `eventCount(runId:)`；测试输入的 `SensorFreshness.runId` 和 `SensorSummary.runId` 必须等于当前 runtime runId。
- `FeatureFlags.v02Default.autoSilenceEnabled == false` 且 `FeatureFlags.v02Default.reSleepDetectionEnabled == false`。

## File Structure

```text
Apps/Watch/Sources/
  WatchAlarmRunEngine.swift
  WatchAppModel.swift
  WatchAlarmRunLogger.swift

Apps/Watch/Tests/
  WatchAlarmRunEngineTests.swift
  WatchAppModelTests.swift

Packages/SmartSleepCore/Tests/SmartSleepCoreTests/
  FeatureFlagsTests.swift
  ReSleepRiskScorerTests.swift
  SmartSleepCoreTests.swift

docs/qa/
  dogfood-runbook.md
  device-test-matrix.md
```

## Task 1: 自动静音两阶段状态机

**Files:**
- Modify: `Apps/Watch/Sources/WatchAlarmRunEngine.swift`
- Test: `Apps/Watch/Tests/WatchAlarmRunEngineTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WatchAlarmRunEngineTests` 增加：

```swift
func testAutoSilenceRequiresCandidateThenConfirmationWindow() {
    let ringer = FakeWatchAlarmRinger()
    let logger = FakeWatchAlarmRunLogger()
    let flags = FeatureFlags(
        autoSilenceEnabled: true,
        reSleepDetectionEnabled: false,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
    let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
    let runId = UUID()
    engine.runtimeDidStart(RuntimeSessionLog(
        runId: runId,
        sessionType: "smartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 0),
        actualStartAt: Date(timeIntervalSince1970: 1),
        invalidatedAt: nil,
        invalidationReason: nil,
        startLatencySec: 1,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: nil,
        errorMessage: nil
    ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
    engine.ringTimeReached(runLogger: logger, at: Date(timeIntervalSince1970: 20))

    let freshness = SensorFreshness.fixture(
        motionLastSampleAgeSec: 1,
        hrLastSampleAgeSec: nil,
        baselineHRConfidence: .none,
        watchWornConfidence: .medium
    )
    let summary = SensorSummary.fixture(
        motionContinuitySec: 12,
        postureDelta: 50,
        gyroPeak: 3,
        stepDelta: 1,
        interactionCount: 1,
        hrDeltaFromBaseline: nil
    )

    let first = engine.evaluateAwake(
        summary: summary,
        freshness: freshness,
        now: Date(timeIntervalSince1970: 23),
        runLogger: logger
    )
    XCTAssertEqual(first?.shouldAutoSilence, true)
    XCTAssertEqual(engine.state, .awakeCandidate)
    XCTAssertEqual(ringer.stopCallCount, 0)

    _ = engine.evaluateAwake(
        summary: summary,
        freshness: freshness,
        now: Date(timeIntervalSince1970: 35),
        runLogger: logger
    )
    XCTAssertEqual(engine.state, .silencedMonitoring)
    XCTAssertEqual(ringer.stopCallCount, 1)
    XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .silencedMonitoring && $0.confidence != nil })
    XCTAssertTrue(logger.channelLogs.contains { $0.stoppedAt == Date(timeIntervalSince1970: 35) && $0.userVisibleState == "auto_silenced" })
    XCTAssertTrue(logger.outcomeLogs.contains { $0.autoSilenceAccepted })
}
```

Expected: FAIL because `evaluateAwake` and candidate timing do not exist.

- [ ] **Step 2: 实现 awake candidate 状态**

在 `WatchAlarmRunEngine` 增加：

```swift
private let awakeScorer = AwakeScorer()
private var awakeCandidateStartedAt: Date?
private var awakeCandidateOriginState: SmartAlarmState?
private let awakeConfirmationWindowSec: Double = 10

func evaluateAwake(
    summary: SensorSummary,
    freshness: SensorFreshness,
    now: Date = Date(),
    runLogger: WatchAlarmRunLogging
) -> AwakeScoreResult? {
    guard featureFlags.autoSilenceEnabled else { return nil }
    guard state == .ringing || state == .reRinging || state == .awakeCandidate else { return nil }
    let result = awakeScorer.evaluate(summary: summary, freshness: freshness)
    guard result.shouldAutoSilence else {
        if state == .awakeCandidate {
            let origin = awakeCandidateOriginState ?? .ringing
            transition(to: origin, reason: "awake_candidate_rejected", at: now, runLogger: runLogger)
            awakeCandidateStartedAt = nil
            awakeCandidateOriginState = nil
        }
        return result
    }
    if state != .awakeCandidate {
        awakeCandidateStartedAt = now
        awakeCandidateOriginState = state
        transition(to: .awakeCandidate, reason: result.reasonCodes.map(\.rawValue).sorted().joined(separator: ","), at: now, runLogger: runLogger, confidence: result.confidence)
        return result
    }
    let elapsed = now.timeIntervalSince(awakeCandidateStartedAt ?? now)
    guard elapsed >= awakeConfirmationWindowSec else { return result }
    ringer.stop()
    silencedAt = now
    awakeCandidateStartedAt = nil
    awakeCandidateOriginState = nil
    recordAutoSilenceChannel(runLogger: runLogger, at: now)
    recordAutoSilenceOutcome(runLogger: runLogger, at: now)
    transition(to: .silencedMonitoring, reason: result.reasonCodes.map(\.rawValue).sorted().joined(separator: ","), at: now, runLogger: runLogger, confidence: result.confidence)
    return result
}
```

调整 `transition` 签名支持 `confidence`：

```swift
private func transition(
    to newState: SmartAlarmState,
    reason: String,
    at date: Date,
    runLogger: WatchAlarmRunLogging?,
    confidence: Double? = nil
)
```

新增自动静音 channel 和 outcome helper：

```swift
private func recordAutoSilenceChannel(runLogger: WatchAlarmRunLogging?, at date: Date) {
    guard let activeRunId else { return }
    try? runLogger?.recordChannel(AlarmChannelLog(
        runId: activeRunId,
        channel: .watchRuntimeHapticAudio,
        scheduledAt: date,
        firedAt: nil,
        stoppedAt: date,
        snoozedAt: nil,
        cancelledAt: nil,
        authorizationState: .authorized,
        failureReason: nil,
        userVisibleState: "auto_silenced"
    ))
}

private func recordAutoSilenceOutcome(runLogger: WatchAlarmRunLogging?, at date: Date) {
    guard let activeRunId else { return }
    try? runLogger?.recordOutcome(OutcomeLabel(
        runId: activeRunId,
        manualStop: false,
        manualSnooze: false,
        gestureSnooze: false,
        autoSilenceAccepted: true,
        falseSilenceReported: false,
        falseReAlarmReported: false,
        missedAlarmReported: false,
        fallbackUsed: false,
        userReportedStillAsleep: false,
        userReportedAwake: false,
        notes: nil,
        labeledAt: date
    ))
}
```

- [ ] **Step 3: 写拒绝测试**

在 `WatchAlarmRunEngineTests` 增加 HR-only 拒绝测试：

```swift
func testAutoSilenceRejectsHeartRateOnlyEvidence() {
    let ringer = FakeWatchAlarmRinger()
    let logger = FakeWatchAlarmRunLogger()
    let flags = FeatureFlags(
        autoSilenceEnabled: true,
        reSleepDetectionEnabled: false,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
    let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
    let runId = UUID()
    engine.runtimeDidStart(RuntimeSessionLog(
        runId: runId,
        sessionType: "smartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 0),
        actualStartAt: Date(timeIntervalSince1970: 1),
        invalidatedAt: nil,
        invalidationReason: nil,
        startLatencySec: 1,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: nil,
        errorMessage: nil
    ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
    engine.ringTimeReached(runLogger: logger, at: Date(timeIntervalSince1970: 20))
    let freshness = SensorFreshness.fixture(
        motionLastSampleAgeSec: 1,
        hrLastSampleAgeSec: 30,
        baselineHRConfidence: .medium,
        watchWornConfidence: .medium
    )
    let summary = SensorSummary.fixture(
        motionContinuitySec: 0,
        postureDelta: 0,
        gyroPeak: 0,
        stepDelta: 0,
        interactionCount: 0,
        hrDeltaFromBaseline: 20
    )

    let result = engine.evaluateAwake(
        summary: summary,
        freshness: freshness,
        now: Date(timeIntervalSince1970: 23),
        runLogger: logger
    )

    XCTAssertEqual(result?.shouldAutoSilence, false)
    XCTAssertEqual(engine.state, .ringing)
    XCTAssertEqual(ringer.stopCallCount, 0)
}
```

再增加 motion stale 拒绝测试：

```swift
func testAutoSilenceRejectsStaleMotionAndReturnsToOriginState() {
    let ringer = FakeWatchAlarmRinger()
    let logger = FakeWatchAlarmRunLogger()
    let flags = FeatureFlags(
        autoSilenceEnabled: true,
        reSleepDetectionEnabled: false,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
    let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
    let runId = UUID()
    engine.runtimeDidStart(RuntimeSessionLog(
        runId: runId,
        sessionType: "smartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 0),
        actualStartAt: Date(timeIntervalSince1970: 1),
        invalidatedAt: nil,
        invalidationReason: nil,
        startLatencySec: 1,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: nil,
        errorMessage: nil
    ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
    engine.ringTimeReached(runLogger: logger, at: Date(timeIntervalSince1970: 20))
    let activeSummary = SensorSummary.fixture(
        motionContinuitySec: 12,
        postureDelta: 50,
        gyroPeak: 3,
        stepDelta: 1,
        interactionCount: 1,
        hrDeltaFromBaseline: nil
    )
    _ = engine.evaluateAwake(
        summary: activeSummary,
        freshness: SensorFreshness.fixture(
            motionLastSampleAgeSec: 1,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        ),
        now: Date(timeIntervalSince1970: 23),
        runLogger: logger
    )
    XCTAssertEqual(engine.state, .awakeCandidate)

    let stale = engine.evaluateAwake(
        summary: activeSummary,
        freshness: SensorFreshness.fixture(
            motionLastSampleAgeSec: 5,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            watchWornConfidence: .medium
        ),
        now: Date(timeIntervalSince1970: 24),
        runLogger: logger
    )

    XCTAssertEqual(stale?.shouldAutoSilence, false)
    XCTAssertEqual(engine.state, .ringing)
    XCTAssertEqual(ringer.stopCallCount, 0)
    XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .ringing && $0.reason == "awake_candidate_rejected" })
}
```

- [ ] **Step 4: 验证**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Then run with XcodeBuildMCP against the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures.

## Task 2: WatchAppModel 用 Summary 驱动自动静音

**Files:**
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Test: `Apps/Watch/Tests/WatchAppModelTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WatchAppModelTests` 增加：

```swift
func testSummaryDrivesAutoSilenceWhenExperimentFlagEnabled() async {
    let alarm = Alarm.fixture(smartEnabled: true)
    let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSinceNow: 3_600))
    let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
    let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
    let ringer = FakeWatchAlarmRinger()
    let logger = FakeWatchAlarmRunLogger()
    let sensorSampler = FakeWatchSensorSampler()
    let flags = FeatureFlags(
        autoSilenceEnabled: true,
        reSleepDetectionEnabled: false,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
    let model = WatchAppModel(
        connectivity: connectivity,
        runtimeScheduler: runtimeScheduler,
        ringer: ringer,
        runLogger: logger,
        sensorSampler: sensorSampler,
        engineFactory: WatchAlarmRunEngineFactory(featureFlags: flags)
    )

    model.armCurrentAlarm()
    let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
    runtimeScheduler.emitStart(RuntimeSessionLog(
        runId: runId,
        sessionType: "fakeSmartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 0),
        actualStartAt: Date(timeIntervalSince1970: 1),
        invalidatedAt: nil,
        invalidationReason: nil,
        startLatencySec: 1,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: nil,
        errorMessage: nil
    ))
    model.simulateRinging()
    var freshness = SensorFreshness.fixture(
        motionLastSampleAgeSec: 1,
        hrLastSampleAgeSec: nil,
        baselineHRConfidence: .none,
        watchWornConfidence: .medium
    )
    freshness.runId = runId
    sensorSampler.emitFreshness(freshness)
    var firstSummary = SensorSummary.fixture(
        motionContinuitySec: 12,
        postureDelta: 50,
        gyroPeak: 3,
        stepDelta: 1,
        interactionCount: 1,
        hrDeltaFromBaseline: nil
    )
    firstSummary.runId = runId
    firstSummary.windowEnd = Date(timeIntervalSince1970: 23)
    sensorSampler.emitSummary(firstSummary)
    await flushMainActorWork()

    XCTAssertEqual(model.currentState, .awakeCandidate)
    XCTAssertEqual(ringer.stopCallCount, 0)

    var secondSummary = SensorSummary.fixture(
        motionContinuitySec: 12,
        postureDelta: 50,
        gyroPeak: 3,
        stepDelta: 1,
        interactionCount: 1,
        hrDeltaFromBaseline: nil
    )
    secondSummary.runId = runId
    secondSummary.windowEnd = Date(timeIntervalSince1970: 35)
    sensorSampler.emitSummary(secondSummary)
    await flushMainActorWork()

    XCTAssertEqual(model.currentState, .silencedMonitoring)
    XCTAssertEqual(ringer.stopCallCount, 1)
    XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .silencedMonitoring })
    XCTAssertTrue(logger.channelLogs.contains { $0.userVisibleState == "auto_silenced" })
    XCTAssertTrue(logger.freshnessLogs.contains { $0.runId == runId && $0.motionFresh })
    XCTAssertTrue(logger.summaryLogs.contains { $0.runId == runId && $0.windowEnd == Date(timeIntervalSince1970: 35) })
}
```

Expected: FAIL because `WatchAppModel` has no engine factory injection and `onSummary` currently does not call `evaluateAwake`.

- [ ] **Step 2: 增加 engine factory 注入**

在 `WatchAppModel.swift` 增加：

```swift
struct WatchAlarmRunEngineFactory {
    var featureFlags: FeatureFlags

    init(featureFlags: FeatureFlags = .v02Default) {
        self.featureFlags = featureFlags
    }

    @MainActor
    func make(initialState: SmartAlarmState, ringer: WatchAlarmRinging) -> WatchAlarmRunEngine {
        WatchAlarmRunEngine(
            initialState: initialState,
            ringer: ringer,
            featureFlags: featureFlags
        )
    }
}
```

在 `WatchAppModel` 增加属性：

```swift
private let engineFactory: WatchAlarmRunEngineFactory
```

把 init 签名扩展为：

```swift
init(
    connectivity: WatchConnectivityClient = WatchConnectivityService(),
    runtimeScheduler: RuntimeSessionScheduling = WatchRuntimeSessionScheduler(),
    ringer: WatchAlarmRinging = WatchAlarmRinger(),
    runLogger: WatchAlarmRunLogging = WatchAlarmRunLogger.temporary(),
    sensorSampler: WatchSensorSampling = CoreMotionWatchSensorSampler(),
    engineFactory: WatchAlarmRunEngineFactory = WatchAlarmRunEngineFactory()
)
```

新增参数：

```swift
engineFactory: WatchAlarmRunEngineFactory = WatchAlarmRunEngineFactory()
```

init body 中赋值：

```swift
self.engineFactory = engineFactory
```

把 `armCurrentAlarm()` 中创建 engine 的代码：

```swift
runEngine = WatchAlarmRunEngine(initialState: .sessionScheduled, ringer: ringer)
```

替换为：

```swift
runEngine = engineFactory.make(initialState: .sessionScheduled, ringer: ringer)
```

更新 `simulateRinging()`，让测试辅助方法同步推进 run engine，而不是只改 `currentState`：

```swift
func simulateRinging() {
    if let runEngine {
        runEngine.ringTimeReached(runLogger: runLogger)
        currentState = runEngine.state
    } else {
        currentState = .ringing
        ringer.startRinging()
    }
}
```

- [ ] **Step 3: 保存最近 freshness**

`WatchAppModel` 增加：

```swift
private var latestFreshness: SensorFreshness?
```

在 `sensorSampler.onFreshness` 中设置 `latestFreshness = freshness`。

- [ ] **Step 4: onSummary 调用 evaluateAwake**

在 `sensorSampler.onSummary` 中：

```swift
self.sensorSampler.onSummary = { [weak self] summary in
    Task { @MainActor in
        guard let self else { return }
        try? self.runLogger.recordSummary(summary)
        guard let freshness = self.latestFreshness,
              let runEngine = self.runEngine else { return }
        if [.ringing, .reRinging, .awakeCandidate].contains(self.currentState) {
            _ = runEngine.evaluateAwake(
                summary: summary,
                freshness: freshness,
                now: summary.windowEnd,
                runLogger: self.runLogger
            )
            self.currentState = runEngine.state
        }
    }
}
```

- [ ] **Step 5: 验证**

Run with XcodeBuildMCP against the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures.

## Task 3: 再睡检测写完整风险日志

**Files:**
- Modify: `Apps/Watch/Sources/WatchAlarmRunEngine.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Test: `Apps/Watch/Tests/WatchAlarmRunEngineTests.swift`
- Test: `Apps/Watch/Tests/WatchAppModelTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WatchAlarmRunEngineTests` 增加：

```swift
func testReSleepRiskReRingsAndLogsRiskReasonAfterGracePeriod() {
    let ringer = FakeWatchAlarmRinger()
    let logger = FakeWatchAlarmRunLogger()
    let flags = FeatureFlags(
        autoSilenceEnabled: true,
        reSleepDetectionEnabled: true,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
    let engine = WatchAlarmRunEngine(ringer: ringer, featureFlags: flags)
    let runId = UUID()
    engine.runtimeDidStart(RuntimeSessionLog(
        runId: runId,
        sessionType: "smartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 0),
        actualStartAt: Date(timeIntervalSince1970: 1),
        invalidatedAt: nil,
        invalidationReason: nil,
        startLatencySec: 1,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: nil,
        errorMessage: nil
    ), nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
    engine.autoSilenceConfirmed(at: Date(timeIntervalSince1970: 0))
    let freshness = SensorFreshness.fixture(
        motionLastSampleAgeSec: 1,
        hrLastSampleAgeSec: nil,
        baselineHRConfidence: .none,
        watchWornConfidence: .medium
    )
    var summary = SensorSummary.fixture(
        motionContinuitySec: 0,
        postureDelta: 1,
        gyroPeak: 0,
        stepDelta: 0,
        interactionCount: 0,
        hrDeltaFromBaseline: nil
    )
    summary.stillnessDurationSec = 180

    let result = engine.evaluateReSleep(
        summary: summary,
        freshness: freshness,
        now: Date(timeIntervalSince1970: 180),
        runLogger: logger
    )

    XCTAssertEqual(result?.shouldReRing, true)
    XCTAssertEqual(engine.state, .reRinging)
    XCTAssertEqual(ringer.startCallCount, 1)
    XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .reRinging && $0.reason.contains("lowMotion") })
    XCTAssertTrue(logger.channelLogs.contains { $0.userVisibleState == "re_ringing" && $0.firedAt == Date(timeIntervalSince1970: 180) })
}
```

Expected: FAIL because `evaluateReSleep` currently has no logger parameter and transition uses `runLogger: nil`.

- [ ] **Step 2: 扩展 evaluateReSleep**

修改签名：

```swift
func evaluateReSleep(
    summary: SensorSummary,
    freshness: SensorFreshness,
    now: Date = Date(),
    runLogger: WatchAlarmRunLogging?
) -> ReSleepRiskResult?
```

当 `shouldReRing` 时：

```swift
let reason = (["re_sleep_risk_detected"] + result.reasonCodes.map(\.rawValue).sorted()).joined(separator: ",")
transition(to: .reRinging, reason: reason, at: now, runLogger: runLogger, confidence: result.riskScore)
ringer.startRinging()
recordReRingChannel(runLogger: runLogger, at: now)
```

日志 reason 使用 `re_sleep_risk_detected`、`lowMotion`、`stablePosture`、`noInteraction`、`noSteps` 等风险原因；不要写“已睡着”。

- [ ] **Step 3: WatchAppModel summary 驱动再睡检测**

在 `WatchAppModelTests` 增加 summary 驱动再睡检测测试：

```swift
func testSummaryDrivesReSleepDetectionWhenExperimentFlagEnabled() async {
    let alarm = Alarm.fixture(smartEnabled: true)
    let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSinceNow: 3_600))
    let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
    let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
    let ringer = FakeWatchAlarmRinger()
    let logger = FakeWatchAlarmRunLogger()
    let sensorSampler = FakeWatchSensorSampler()
    let flags = FeatureFlags(
        autoSilenceEnabled: true,
        reSleepDetectionEnabled: true,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
    let model = WatchAppModel(
        connectivity: connectivity,
        runtimeScheduler: runtimeScheduler,
        ringer: ringer,
        runLogger: logger,
        sensorSampler: sensorSampler,
        engineFactory: WatchAlarmRunEngineFactory(featureFlags: flags)
    )

    model.armCurrentAlarm()
    let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
    runtimeScheduler.emitStart(RuntimeSessionLog(
        runId: runId,
        sessionType: "fakeSmartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 0),
        actualStartAt: Date(timeIntervalSince1970: 1),
        invalidatedAt: nil,
        invalidationReason: nil,
        startLatencySec: 1,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: nil,
        errorMessage: nil
    ))
    model.simulateRinging()
    var freshness = SensorFreshness.fixture(
        motionLastSampleAgeSec: 1,
        hrLastSampleAgeSec: nil,
        baselineHRConfidence: .none,
        watchWornConfidence: .medium
    )
    freshness.runId = runId
    sensorSampler.emitFreshness(freshness)
    var awakeSummary = SensorSummary.fixture(
        motionContinuitySec: 12,
        postureDelta: 50,
        gyroPeak: 3,
        stepDelta: 1,
        interactionCount: 1,
        hrDeltaFromBaseline: nil
    )
    awakeSummary.runId = runId
    awakeSummary.windowEnd = Date(timeIntervalSince1970: 23)
    sensorSampler.emitSummary(awakeSummary)
    awakeSummary.windowEnd = Date(timeIntervalSince1970: 35)
    sensorSampler.emitSummary(awakeSummary)
    await flushMainActorWork()
    XCTAssertEqual(model.currentState, .silencedMonitoring)

    var reSleepSummary = SensorSummary.fixture(
        motionContinuitySec: 0,
        postureDelta: 1,
        gyroPeak: 0,
        stepDelta: 0,
        interactionCount: 0,
        hrDeltaFromBaseline: nil
    )
    reSleepSummary.runId = runId
    reSleepSummary.stillnessDurationSec = 180
    reSleepSummary.windowEnd = Date(timeIntervalSince1970: 220)
    sensorSampler.emitSummary(reSleepSummary)
    await flushMainActorWork()

    XCTAssertEqual(model.currentState, .reRinging)
    XCTAssertEqual(ringer.startCallCount, 2)
    XCTAssertTrue(logger.stateTransitionLogs.contains { $0.toState == .reRinging && $0.reason.contains("re_sleep_risk_detected") })
    XCTAssertTrue(logger.freshnessLogs.contains { $0.runId == runId && $0.motionFresh })
    XCTAssertTrue(logger.summaryLogs.contains {
        $0.runId == runId
            && $0.stillnessDurationSec == 180
            && $0.stepDelta == 0
            && $0.interactionCount == 0
    })
}
```

在 `onSummary` 中，当 `currentState == .silencedMonitoring` 且有 latest freshness：

```swift
if self.currentState == .silencedMonitoring {
    _ = runEngine.evaluateReSleep(
        summary: summary,
        freshness: freshness,
        now: summary.windowEnd,
        runLogger: self.runLogger
    )
    self.currentState = runEngine.state
}
```

在进入 `.reRinging` 时记录 channel log。状态转换的 `confidence` 使用 `result.riskScore`，reason 必须包含 `re_sleep_risk_detected` 和具体 reason code。给 `WatchAlarmRunEngine` 增加：

```swift
private func recordReRingChannel(runLogger: WatchAlarmRunLogging?, at date: Date) {
    guard let activeRunId else { return }
    try? runLogger?.recordChannel(AlarmChannelLog(
        runId: activeRunId,
        channel: .watchRuntimeHapticAudio,
        scheduledAt: date,
        firedAt: date,
        stoppedAt: nil,
        snoozedAt: nil,
        cancelledAt: nil,
        authorizationState: .authorized,
        failureReason: nil,
        userVisibleState: "re_ringing"
    ))
}
```

在 `evaluateReSleep(...)` 中 `ringer.startRinging()` 后调用 `recordReRingChannel(runLogger: runLogger, at: now)`。不要记录“已睡着”；只记录风险原因和 risk score。触发再睡重响前，`WatchAppModel` 必须已经写入同一 runId 的 freshness 和 summary，这样 JSONL 能回放 `stillnessDurationSec`、`stepDelta`、`interactionCount` 和 motion freshness。

- [ ] **Step 4: 验证默认关闭**

确认 `FeatureFlagsTests.testDefaultFlagsKeepExperimentalBehaviorConservative` 仍断言：

```swift
XCTAssertFalse(flags.autoSilenceEnabled)
XCTAssertFalse(flags.reSleepDetectionEnabled)
```

- [ ] **Step 5: 验证**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Then run with XcodeBuildMCP against the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures.

## Task 4: Dogfood Gate 更新

**Files:**
- Modify: `docs/qa/dogfood-runbook.md`
- Modify: `docs/qa/device-test-matrix.md`

- [ ] **Step 1: 更新 dogfood 阻断条件**

写明：自动静音和再睡检测只允许命名内部 run 开启。每个 run 必须导出 JSONL，包含 state transition、channel、runtime、sensor freshness、sensor summary、outcome。

- [ ] **Step 2: 更新真机矩阵**

增加以下真机列项：auto silence false positive、HR-only rejected、motion stale rejected、re-sleep false re-alarm、max re-alarm count、feature flag state。每项必须记录日期、设备、系统版本、run id、结果。

- [ ] **Step 3: 验证文案**

搜索文档不得出现“已睡着”作为算法判断结论：

```bash
rg -n "已睡着|睡眠阶段|诊断" docs/qa docs/spikes docs/superpowers/plans
```

Expected: 没有把再睡风险写成睡眠阶段或医疗诊断。

## Final Verification

- [ ] `SmartSleepCore` tests 通过。
- [ ] `SmartSleepWatch` tests 通过。
- [ ] 自动静音两阶段测试覆盖 candidate 和 confirmation window。
- [ ] HR-only 和 motion stale 均不会自动静音。
- [ ] 再睡检测日志包含 risk score/reason，不出现“已睡着”判断。
- [ ] v0.2 默认 flags 仍关闭自动静音和再睡检测。

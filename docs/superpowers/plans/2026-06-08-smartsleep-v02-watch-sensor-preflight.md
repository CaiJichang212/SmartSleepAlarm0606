# Watch Sensor Summary and Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成 Watch arming preflight、CoreMotion summary 聚合和 HealthKit heart-rate freshness mapper，为后续实验能力提供可回放传感器输入。

**Architecture:** Watch preflight 只检查配置、motion 可用性、电量和 runtime 预约前置条件，不因为 HealthKit denied 阻止 Smart Mode。preflight 失败不调用 runtime scheduler，但仍创建 runId、记录状态转换、发送 session result 和 run summary，保证可回放；时间判断必须可测试，现有 Watch 测试要显式注入通过的 fake preflight 或使用未来时间。CoreMotion 聚合逻辑拆成纯 Swift helper 便于测试；HealthKit 本轮只交付 mapper、协议和保守查询 adapter，真机数据质量作为独立 spike。

**Tech Stack:** Swift 6.1, XCTest, WatchKit, CoreMotion, HealthKit, JSONL logs, XcodeBuildMCP.

---

## File Structure

```text
Apps/Watch/Sources/
  WatchPreflightChecker.swift
  WatchSensorSampler.swift
  WatchHealthKitHeartRateSampler.swift
  WatchAppModel.swift
  WatchAlarmRunLogger.swift

Apps/Watch/Tests/
  WatchPreflightCheckerTests.swift
  WatchAppModelTests.swift
  WatchSensorSamplerTests.swift
  WatchHealthKitHeartRateSamplerTests.swift
  WatchAlarmRunLoggerTests.swift

docs/qa/
  device-test-matrix.md
```

## Task 1: Watch Arming Preflight

**Files:**
- Create: `Apps/Watch/Sources/WatchPreflightChecker.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Test: `Apps/Watch/Tests/WatchAppModelTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WatchAppModelTests` 增加：

```swift
func testLowBatteryPreflightFailsClosedBeforeSchedulingRuntime() {
    let alarm = Alarm.fixture(smartEnabled: true)
    let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date.now.addingTimeInterval(3_600))
    let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
    let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
    let preflight = FakeWatchPreflightChecker(result: WatchPreflightResult(
        canArmSmartMode: false,
        batteryLevel: 0.08,
        motionAvailable: true,
        failureReason: "watch_battery_low"
    ))
    let model = WatchAppModel(
        connectivity: connectivity,
        runtimeScheduler: runtimeScheduler,
        ringer: FakeWatchAlarmRinger(),
        preflightChecker: preflight
    )

    model.armCurrentAlarm()

    XCTAssertEqual(model.currentState, .fallbackPhoneAlarm)
    XCTAssertFalse(model.sessionScheduled)
    XCTAssertEqual(model.failureReason, "watch_battery_low")
    XCTAssertNil(runtimeScheduler.lastRunID)
    let arming = connectivity.outboundMessages.compactMap { message -> ArmingResultPayload? in
        guard case let .armingResult(payload) = message else { return nil }
        return payload
    }.last
    XCTAssertEqual(arming?.status.isArmed, false)
    XCTAssertEqual(arming?.status.sessionScheduled, false)

    let sessionResults = connectivity.outboundMessages.compactMap { message -> SessionResultPayload? in
        guard case let .sessionResult(payload) = message else { return nil }
        return payload
    }
    let sessionResult = try! XCTUnwrap(sessionResults.last)
    XCTAssertEqual(sessionResult.alarmId, alarm.id)
    XCTAssertEqual(sessionResult.state, .fallbackPhoneAlarm)
    XCTAssertEqual(sessionResult.failureReason, "watch_battery_low")

    let summaries = connectivity.outboundMessages.compactMap { message -> RunLogSummaryPayload? in
        guard case let .runLogSummary(payload) = message else { return nil }
        return payload
    }
    let summary = try! XCTUnwrap(summaries.last)
    XCTAssertEqual(summary.runId, sessionResult.runId)
    XCTAssertEqual(summary.finalState, .fallbackPhoneAlarm)
    XCTAssertTrue(summary.fallbackUsed)
}
```

Expected: FAIL because `WatchPreflightChecker` and `preflightChecker` injection do not exist, and preflight failure does not send session/run summary.

- [ ] **Step 2: 定义 preflight 类型和协议**

创建 `WatchPreflightChecker.swift`：

```swift
import CoreMotion
import Foundation
import SmartSleepCore
import WatchKit

struct WatchPreflightResult: Equatable, Sendable {
    var canArmSmartMode: Bool
    var batteryLevel: Double?
    var motionAvailable: Bool
    var failureReason: String?
}

protocol WatchPreflightChecking {
    func check(nextFireAt: Date, now: Date) -> WatchPreflightResult
}

struct WatchPreflightChecker: WatchPreflightChecking {
    func check(nextFireAt: Date, now: Date = Date()) -> WatchPreflightResult {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let battery = Double(device.batteryLevel)
        if battery >= 0, battery < 0.10 {
            return WatchPreflightResult(
                canArmSmartMode: false,
                batteryLevel: battery,
                motionAvailable: CMMotionManager().isDeviceMotionAvailable,
                failureReason: "watch_battery_low"
            )
        }
        let motionAvailable = CMMotionManager().isDeviceMotionAvailable
        if !motionAvailable {
            return WatchPreflightResult(
                canArmSmartMode: false,
                batteryLevel: battery >= 0 ? battery : nil,
                motionAvailable: false,
                failureReason: "motion_unavailable"
            )
        }
        if nextFireAt <= now {
            return WatchPreflightResult(
                canArmSmartMode: false,
                batteryLevel: battery >= 0 ? battery : nil,
                motionAvailable: motionAvailable,
                failureReason: "alarm_time_not_in_future"
            )
        }
        return WatchPreflightResult(
            canArmSmartMode: true,
            batteryLevel: battery >= 0 ? battery : nil,
            motionAvailable: motionAvailable,
            failureReason: nil
        )
    }
}
```

不要把 fake 放入 `Apps/Watch/Sources`。在 `Apps/Watch/Tests/WatchPreflightCheckerTests.swift` 或 `WatchAppModelTests.swift` 测试文件内增加：

```swift
final class FakeWatchPreflightChecker: WatchPreflightChecking {
    var result: WatchPreflightResult
    init(result: WatchPreflightResult) { self.result = result }
    func check(nextFireAt: Date, now: Date) -> WatchPreflightResult { result }
}
```

新增纯 preflight 时间测试，防止未来/过去时间判断依赖真实当前时间：

```swift
final class WatchPreflightCheckerTests: XCTestCase {
    func testPastAlarmTimeFailsPreflightWithInjectedNow() {
        let checker = WatchPreflightChecker()

        let result = checker.check(
            nextFireAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertFalse(result.canArmSmartMode)
        XCTAssertEqual(result.failureReason, "alarm_time_not_in_future")
    }
}
```

- [ ] **Step 3: 接入 WatchAppModel**

`WatchAppModel` 增加属性：

```swift
private let preflightChecker: WatchPreflightChecking
```

把 init 签名扩展为：

```swift
init(
    connectivity: WatchConnectivityClient = WatchConnectivityService(),
    runtimeScheduler: RuntimeSessionScheduling = WatchRuntimeSessionScheduler(),
    ringer: WatchAlarmRinging = WatchAlarmRinger(),
    runLogger: WatchAlarmRunLogging = WatchAlarmRunLogger.temporary(),
    sensorSampler: WatchSensorSampling = CoreMotionWatchSensorSampler(),
    preflightChecker: WatchPreflightChecking = WatchPreflightChecker()
)
```

新增参数：

```swift
preflightChecker: WatchPreflightChecking = WatchPreflightChecker()
```

init body 中赋值：

```swift
self.preflightChecker = preflightChecker
```

在 `armCurrentAlarm()` 中，拿到 config 后先创建 runId，再 schedule runtime。把当前这段：

```swift
let runId = UUID()
activeAlarmID = config.alarm.id
activeRunID = runId
let runtimeLog = runtimeScheduler.schedule(for: config, runId: runId)
```

替换为：

```swift
let runId = UUID()
activeAlarmID = config.alarm.id
activeRunID = runId

let preflight = preflightChecker.check(nextFireAt: config.nextFireAt, now: Date())
guard preflight.canArmSmartMode else {
    sessionScheduled = false
    failureReason = preflight.failureReason ?? "watch_preflight_failed"
    transitionState(
        to: .fallbackPhoneAlarm,
        reason: failureReason ?? "watch_preflight_failed",
        errorCode: failureReason
    )
    let status = WatchArmingStatus(
        alarmId: config.alarm.id,
        isArmed: false,
        sessionScheduled: false,
        fallbackChannel: .iOSLocalNotification,
        failureReason: failureReason
    )
    connectivity.sendArmingResult(ArmingResultPayload(alarmId: config.alarm.id, armedAt: Date(), status: status))
    connectivity.sendSessionResult(SessionResultPayload(
        alarmId: config.alarm.id,
        runId: runId,
        state: currentState,
        scheduledAt: nil,
        failureReason: failureReason
    ))
    sendRunSummary(outcome: nil, fallbackUsed: true)
    return
}

let runtimeLog = runtimeScheduler.schedule(for: config, runId: runId)
```

`sendRunSummary(outcome:fallbackUsed:)` 来自 `watch-ios-connectivity-run-summary` 计划。preflight failure 不写 `RuntimeSessionLog`，因为 runtime scheduler 没有被调用；失败事实由 `StateTransitionLog`、`SessionResultPayload` 和 `RunLogSummaryPayload` 回放。

不要在 preflight 中检查 HealthKit 授权。HealthKit denied 不阻塞 motion-only Smart Mode。

- [ ] **Step 3b: 修正既有 WatchAppModel 测试基线**

新增 preflight 注入后，更新所有不是测试 preflight failure 的 `WatchAppModelTests`：

```swift
let passingPreflight = FakeWatchPreflightChecker(result: WatchPreflightResult(
    canArmSmartMode: true,
    batteryLevel: 0.80,
    motionAvailable: true,
    failureReason: nil
))
let model = WatchAppModel(
    connectivity: connectivity,
    runtimeScheduler: runtimeScheduler,
    ringer: FakeWatchAlarmRinger(),
    runLogger: logger,
    sensorSampler: sensorSampler,
    preflightChecker: passingPreflight
)
```

如果测试不需要验证 preflight，`AlarmConfigPayload.nextFireAt` 使用 `Date.now.addingTimeInterval(3_600)`，不要再使用 `Date(timeIntervalSince1970: 3_600)` 假装未来时间。

- [ ] **Step 4: 验证**

Run with XcodeBuildMCP:

```text
session_show_defaults()
list_sims(enabled: true)
list_schemes(projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj")
```

Then run the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures.

## Task 2: Logger 支持 Sensor Summary

**Files:**
- Modify: `Apps/Watch/Sources/WatchAlarmRunLogger.swift`
- Test: `Apps/Watch/Tests/WatchAlarmRunLoggerTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WatchAlarmRunLoggerTests` 增加：

```swift
func testLoggerExportsSensorSummaryEvents() throws {
    let logger = try WatchAlarmRunLogger(logsDirectory: temporaryDirectoryURL())
    var summary = SensorSummary.fixture(
        motionContinuitySec: 12,
        postureDelta: 30,
        gyroPeak: 2,
        stepDelta: 0,
        interactionCount: 0,
        hrDeltaFromBaseline: nil
    )
    let runId = UUID()
    summary.runId = runId

    try logger.recordSummary(summary)

    let exported = try logger.export(runId: runId)
    XCTAssertTrue(exported.contains("sensorSummary"))
}
```

Expected: FAIL because `recordSummary(_:)` does not exist.

- [ ] **Step 2: 扩展 WatchAlarmRunLogging**

新增：

```swift
func recordSummary(_ summary: SensorSummary) throws
```

真实 logger：

```swift
func recordSummary(_ summary: SensorSummary) throws {
    let store = try JSONLAlarmEventStore(directory: logsDirectory)
    try store.append(.sensorSummary(summary), recordedAt: summary.windowEnd)
}
```

fake logger 增加：

```swift
private(set) var summaryLogs: [SensorSummary] = []
func recordSummary(_ summary: SensorSummary) throws { summaryLogs.append(summary) }
```

本计划按顺序在连接计划之后执行，因此把 `summaryLogs` 纳入 fake logger 的 `eventCount(runId:)` 计数。

- [ ] **Step 3: 验证**

Run with XcodeBuildMCP against the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures.

## Task 3: CoreMotion Summary Aggregator

**Files:**
- Modify: `Apps/Watch/Sources/WatchSensorSampler.swift`
- Test: `Apps/Watch/Tests/WatchSensorSamplerTests.swift`

- [ ] **Step 1: 写纯 Swift 聚合测试**

在 `WatchSensorSamplerTests` 增加：

```swift
func testMotionWindowAggregatorBuildsSummaryFromSamples() {
    var aggregator = MotionWindowAggregator(
        runId: UUID(),
        windowStart: Date(timeIntervalSince1970: 0)
    )
    aggregator.append(MotionWindowSample(
        timestamp: Date(timeIntervalSince1970: 1),
        accelMagnitude: 0.1,
        gyroMagnitude: 0.2,
        attitudeRoll: 0,
        attitudePitch: 0,
        attitudeYaw: 0
    ))
    aggregator.append(MotionWindowSample(
        timestamp: Date(timeIntervalSince1970: 2),
        accelMagnitude: 1.0,
        gyroMagnitude: 3.5,
        attitudeRoll: 0.8,
        attitudePitch: 0,
        attitudeYaw: 0
    ))

    let summary = aggregator.summary(windowEnd: Date(timeIntervalSince1970: 3))

    XCTAssertGreaterThan(summary.accelMagnitudeMean, 0.5)
    XCTAssertEqual(summary.gyroPeak, 3.5, accuracy: 0.001)
    XCTAssertGreaterThan(summary.postureDelta, 40)
}
```

Expected: FAIL because `MotionWindowAggregator` does not exist.

- [ ] **Step 2: 实现聚合 helper**

在 `WatchSensorSampler.swift` 新增：

```swift
struct MotionWindowSample: Equatable {
    var timestamp: Date
    var accelMagnitude: Double
    var gyroMagnitude: Double
    var attitudeRoll: Double
    var attitudePitch: Double
    var attitudeYaw: Double
}

struct MotionWindowAggregator {
    let runId: UUID
    let windowStart: Date
    private(set) var samples: [MotionWindowSample] = []

    mutating func append(_ sample: MotionWindowSample) {
        samples.append(sample)
    }

    func summary(windowEnd: Date) -> SensorSummary {
        let accel = samples.map(\.accelMagnitude)
        let gyro = samples.map(\.gyroMagnitude)
        let mean = accel.isEmpty ? 0 : accel.reduce(0, +) / Double(accel.count)
        let variance = accel.isEmpty ? 0 : accel.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accel.count)
        let gyroMean = gyro.isEmpty ? 0 : gyro.reduce(0, +) / Double(gyro.count)
        let gyroPeak = gyro.max() ?? 0
        let postureDelta = Self.postureDeltaDegrees(samples)
        let motionContinuitySec = samples.filter { $0.accelMagnitude > 0.2 || $0.gyroMagnitude > 0.5 }.count > 0
            ? windowEnd.timeIntervalSince(windowStart)
            : 0
        let stillnessDurationSec = samples.allSatisfy { $0.accelMagnitude < 0.05 && $0.gyroMagnitude < 0.1 }
            ? windowEnd.timeIntervalSince(windowStart)
            : 0
        return SensorSummary(
            runId: runId,
            windowStart: windowStart,
            windowEnd: windowEnd,
            baselineHR: nil,
            baselineMotion: mean,
            accelMagnitudeMean: mean,
            accelMagnitudeStd: sqrt(variance),
            gyroMagnitudeMean: gyroMean,
            gyroPeak: gyroPeak,
            postureDelta: postureDelta,
            motionContinuitySec: motionContinuitySec,
            stillnessDurationSec: stillnessDurationSec,
            stepDelta: 0,
            screenWakeCount: 0,
            interactionCount: 0,
            missingDataDurationSec: 0,
            batteryDelta: 0,
            hrDeltaFromBaseline: nil
        )
    }

    private static func postureDeltaDegrees(_ samples: [MotionWindowSample]) -> Double {
        guard let first = samples.first, let last = samples.last else { return 0 }
        let delta = abs(last.attitudeRoll - first.attitudeRoll)
            + abs(last.attitudePitch - first.attitudePitch)
            + abs(last.attitudeYaw - first.attitudeYaw)
        return delta * 180 / .pi
    }
}
```

- [ ] **Step 3: CoreMotion sampler emit summary**

在 `CoreMotionWatchSensorSampler` 增加属性：

```swift
private var aggregator: MotionWindowAggregator?
private var lastSummaryAt: Date?
private let summaryWindowSec: TimeInterval = 3
```

在 `start(runId:)` 初始化：

```swift
let start = Date()
windowStart = start
lastSummaryAt = start
aggregator = MotionWindowAggregator(runId: runId, windowStart: start)
```

在 `startDeviceMotionUpdates` closure 中计算 `accelMagnitude` 和 `gyroMagnitude` 后追加样本：

```swift
self.aggregator?.append(MotionWindowSample(
    timestamp: now,
    accelMagnitude: accelMagnitude,
    gyroMagnitude: gyroMagnitude,
    attitudeRoll: motion.attitude.roll,
    attitudePitch: motion.attitude.pitch,
    attitudeYaw: motion.attitude.yaw
))
if let lastSummaryAt = self.lastSummaryAt,
   now.timeIntervalSince(lastSummaryAt) >= self.summaryWindowSec,
   let summary = self.aggregator?.summary(windowEnd: now),
   !summary.isHighConfidenceEmptyWindow {
    self.onSummary?(summary)
    self.lastSummaryAt = now
    self.aggregator = MotionWindowAggregator(runId: runId, windowStart: now)
}
```

给 `SensorSummary` 在 `WatchSensorSampler.swift` 增加 file-private helper，避免无样本窗口被误当作高置信输入：

```swift
private extension SensorSummary {
    var isHighConfidenceEmptyWindow: Bool {
        motionContinuitySec == 0
            && accelMagnitudeMean == 0
            && gyroMagnitudeMean == 0
            && gyroPeak == 0
            && postureDelta == 0
    }
}
```

在 `stop()` 中清理：

```swift
aggregator = nil
lastSummaryAt = nil
```

- [ ] **Step 4: WatchAppModel 记录 summary**

在 `WatchAppModel` init 增加：

```swift
self.sensorSampler.onSummary = { [weak self] summary in
    Task { @MainActor in
        try? self?.runLogger.recordSummary(summary)
    }
}
```

- [ ] **Step 5: 验证**

Run with XcodeBuildMCP against the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures.

## Task 4: HealthKit Heart Rate Freshness Mapper and Conservative Adapter

**Files:**
- Create: `Apps/Watch/Sources/WatchHealthKitHeartRateSampler.swift`
- Modify: `Apps/Watch/Info.plist`
- Test: `Apps/Watch/Tests/WatchHealthKitHeartRateSamplerTests.swift`
- Docs: `docs/qa/device-test-matrix.md`

- [ ] **Step 1: 写 fake mapping 测试**

创建 `WatchHealthKitHeartRateSamplerTests.swift`：

```swift
import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

final class WatchHealthKitHeartRateSamplerTests: XCTestCase {
    func testFreshHeartRateMapsToUsableFreshnessValues() {
        let runId = UUID()
        let now = Date(timeIntervalSince1970: 200)
        let sample = HeartRateSample(
            bpm: 72,
            sampledAt: Date(timeIntervalSince1970: 140),
            baselineBPM: 60,
            baselineConfidence: .medium
        )

        let freshness = HeartRateFreshnessMapper.freshness(
            runId: runId,
            now: now,
            sample: sample,
            motionSampleCount: 20,
            motionLastSampleAgeSec: 1,
            watchWornConfidence: .medium
        )

        XCTAssertEqual(freshness.hrSampleCount, 1)
        XCTAssertEqual(freshness.hrLastSampleAgeSec, 60)
        XCTAssertEqual(freshness.baselineHRConfidence, .medium)
        XCTAssertTrue(freshness.heartRateUsable)
    }

    func testDeniedAuthorizationDoesNotDisableMotionFreshness() async {
        let sampler = FakeWatchHeartRateSampler(
            authorization: .denied,
            latestHeartRateSample: nil
        )

        let authorization = await sampler.authorizationState()
        let freshness = HeartRateFreshnessMapper.freshness(
            runId: UUID(),
            now: Date(timeIntervalSince1970: 200),
            sample: sampler.latestHeartRateSample,
            motionSampleCount: 20,
            motionLastSampleAgeSec: 1,
            watchWornConfidence: .medium
        )

        XCTAssertEqual(authorization, .denied)
        XCTAssertEqual(freshness.hrSampleCount, 0)
        XCTAssertFalse(freshness.heartRateUsable)
        XCTAssertTrue(freshness.motionFresh)
    }
}
```

Expected: FAIL because HR mapper/types do not exist.

- [ ] **Step 2: 定义协议和 mapper**

```swift
import Foundation
import HealthKit
import SmartSleepCore

protocol WatchHeartRateSampling: AnyObject {
    var latestHeartRateSample: HeartRateSample? { get }
    func authorizationState() async -> AuthorizationState
    func start()
    func stop()
}

struct HeartRateSample: Equatable, Sendable {
    var bpm: Double
    var sampledAt: Date
    var baselineBPM: Double?
    var baselineConfidence: ConfidenceLevel
}

enum HeartRateFreshnessMapper {
    static func freshness(
        runId: UUID,
        now: Date,
        sample: HeartRateSample?,
        motionSampleCount: Int,
        motionLastSampleAgeSec: Double,
        watchWornConfidence: ConfidenceLevel
    ) -> SensorFreshness {
        SensorFreshness(
            runId: runId,
            timestamp: now,
            motionSampleCount: motionSampleCount,
            motionLastSampleAgeSec: motionLastSampleAgeSec,
            hrSampleCount: sample == nil ? 0 : 1,
            hrLastSampleAgeSec: sample.map { now.timeIntervalSince($0.sampledAt) },
            baselineHRConfidence: sample?.baselineConfidence ?? .none,
            baselineMotionConfidence: motionSampleCount >= 10 ? .medium : .low,
            watchWornConfidence: watchWornConfidence,
            sensorConfidence: motionLastSampleAgeSec <= 2 ? .medium : .low
        )
    }
}

```

不要把 `FakeWatchHeartRateSampler` 放入 `Apps/Watch/Sources`。在 `Apps/Watch/Tests/WatchHealthKitHeartRateSamplerTests.swift` 测试文件内增加：

```swift
final class FakeWatchHeartRateSampler: WatchHeartRateSampling {
    private let authorization: AuthorizationState
    private(set) var latestHeartRateSample: HeartRateSample?

    init(authorization: AuthorizationState, latestHeartRateSample: HeartRateSample?) {
        self.authorization = authorization
        self.latestHeartRateSample = latestHeartRateSample
    }

    func authorizationState() async -> AuthorizationState { authorization }
    func start() {}
    func stop() {}
}
```

- [ ] **Step 3: 实现保守 HealthKit adapter**

在 `WatchHealthKitHeartRateSampler.swift` 增加：

```swift
final class WatchHealthKitHeartRateSampler: WatchHeartRateSampling {
    private let healthStore = HKHealthStore()
    private var query: HKSampleQuery?
    private(set) var latestHeartRateSample: HeartRateSample?

    func authorizationState() async -> AuthorizationState {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return .unavailable
        }
        switch healthStore.authorizationStatus(for: type) {
        case .notDetermined:
            return .notDetermined
        case .sharingAuthorized:
            return .authorized
        case .sharingDenied:
            return .denied
        @unknown default:
            return .unknown
        }
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            latestHeartRateSample = nil
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { [weak self] _, samples, _ in
            guard let quantitySample = samples?.first as? HKQuantitySample else { return }
            let bpm = quantitySample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            self?.latestHeartRateSample = HeartRateSample(
                bpm: bpm,
                sampledAt: quantitySample.endDate,
                baselineBPM: nil,
                baselineConfidence: .low
            )
        }
        self.query = query
        healthStore.execute(query)
    }

    func stop() {
        if let query {
            healthStore.stop(query)
        }
        query = nil
    }
}
```

这只是最近样本查询 adapter，不启动 workout session，不承诺秒级心率。`authorizationState() == .denied` 时只禁用 HR boost，不能让 Watch arming 失败。

- [ ] **Step 4: 权限文案和真机记录**

在 `Apps/Watch/Info.plist` 添加 HealthKit 用途说明：

```xml
<key>NSHealthShareUsageDescription</key>
<string>SmartSleep uses recent heart-rate samples only as an optional confidence boost for wake detection.</string>
```

更新 `docs/qa/device-test-matrix.md`：HR freshness 必须在真机记录 `hrLastSampleAgeSec`、`baselineHRConfidence`、授权状态和 run id。增加独立 spike 行：真机验证 `HKSampleQuery` 最近心率样本可用性、授权拒绝路径、样本延迟分布；验证完成前不得把 HR 作为 auto silence 的必要条件。

- [ ] **Step 5: 验证**

Regenerate the Xcode project after changing `Apps/Watch/Info.plist`:

```bash
xcodegen generate
```

Run with XcodeBuildMCP against the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures. 真实 HealthKit 数据仍标记为真机验证项。

## Final Verification

- [ ] `SmartSleepWatch` scheme 测试通过。
- [ ] 新增 preflight 不检查 HealthKit 授权。
- [ ] `recordSummary(_:)` 和 `eventCount(runId:)` 已实现，fake logger 与真实 logger 行为一致。
- [ ] CoreMotion 无样本时不生成高置信 summary。
- [ ] HealthKit denied 不禁用 motion-only Smart Mode。

# Watch-iOS Connectivity and Run Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 iOS 端可靠消费 Watch 回传的 session result 和 run summary，并让 Watch summary 的 event count 来自真实日志计数。

**Architecture:** 保持 `SmartSleepCore` 的 payload 不变，扩展 iOS/Watch 壳层协议。iOS 不覆盖 Watch arming 历史状态，而是把 `SessionResultPayload` 作为单独事实源按 `alarmId` 合并到卡片展示；`RunLogSummaryPayload` 按 `runId` 保存，latest summary 只用于内部调试区。Watch logger 增加 `eventCount(runId:)`，run summary 只从 logger 读取事件数；用户 stop/snooze、runtime invalidation 和主动取消都要发 summary。

**Tech Stack:** Swift 6.1, SwiftUI, XCTest, WatchConnectivity, JSONL logs, XcodeGen, XcodeBuildMCP.

---

## File Structure

```text
Apps/iOS/Sources/
  IOSConnectivityService.swift       receive sessionResult and runLogSummary
  AppModel.swift                     store sessionResults and runSummaries
  SmartSleepAlarmApp.swift           show recent session/run summary state

Apps/iOS/Tests/
  AlarmDashboardModelTests.swift     model-level session/run summary tests

Apps/Watch/Sources/
  WatchAlarmRunLogger.swift          add eventCount(runId:)
  WatchAppModel.swift                send run summary after terminal user actions

Apps/Watch/Tests/
  WatchAlarmRunLoggerTests.swift
  WatchAppModelTests.swift
```

## Task 1: iOS 接收 Session Result 不覆盖 Arming

**Files:**
- Modify: `Apps/iOS/Sources/IOSConnectivityService.swift`
- Modify: `Apps/iOS/Sources/AppModel.swift`
- Test: `Apps/iOS/Tests/AlarmDashboardModelTests.swift`

- [ ] **Step 1: 写失败测试**

在 `AlarmDashboardModelTests` 增加：

```swift
func testModelAppliesSessionFailureWithoutOverwritingArmingStatus() async throws {
    let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
    let connectivity = FakePhoneConnectivityClient()
    let model = AlarmDashboardModel(
        repository: repository,
        notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
        backupScheduler: RecordingBackupAlarmScheduler(),
        connectivity: connectivity,
        runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
    )
    let created = AlarmCardState.make(
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        label: "Runtime Failure",
        smartEnabled: true,
        snoozeMinutes: 9
    )

    await model.refreshNotificationAuthorization()
    model.create(created)
    await flushMainActorWork()

    connectivity.deliverArmingStatus(WatchArmingStatus(
        alarmId: created.id,
        isArmed: true,
        sessionScheduled: true,
        fallbackChannel: .iOSLocalNotification,
        failureReason: nil
    ))
    connectivity.deliverSessionResult(SessionResultPayload(
        alarmId: created.id,
        runId: UUID(),
        state: .fallbackPhoneAlarm,
        scheduledAt: Date(timeIntervalSince1970: 10),
        failureReason: "runtime_session_invalidated"
    ))
    await flushMainActorWork()

    let updated = try XCTUnwrap(model.alarms.first { $0.id == created.id })
    XCTAssertEqual(updated.armingStatus?.isArmed, true)
    XCTAssertEqual(updated.armingStatus?.sessionScheduled, true)
    XCTAssertEqual(updated.sessionResult?.failureReason, "runtime_session_invalidated")
    XCTAssertEqual(updated.smartStatus, .fallbackOnly)
    XCTAssertEqual(model.userVisibleWarning, "Watch runtime unavailable; iPhone fallback is active. runtime_session_invalidated")
}
```

Run with XcodeBuildMCP:

```text
session_show_defaults()
list_sims(enabled: true)
list_schemes(projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj")
```

Then run the `SmartSleepAlarm` scheme on an available iOS Simulator returned by `list_sims`. On the current machine, `list_sims(enabled: true)` includes `iPhone 16 Pro` with simulatorId `FD770DCA-02E9-4FE8-A924-2AC0C699A2DE`, so the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,id=FD770DCA-02E9-4FE8-A924-2AC0C699A2DE'
```

Expected: FAIL with missing `deliverSessionResult`, `sessionResult`, and session result handling.

- [ ] **Step 2: 扩展 PhoneConnectivityClient**

在 `Apps/iOS/Sources/IOSConnectivityService.swift` 修改协议：

```swift
protocol PhoneConnectivityClient: AnyObject {
    var lastArmingStatus: WatchArmingStatus? { get }
    var lastSessionResult: SessionResultPayload? { get }
    var lastRunLogSummary: RunLogSummaryPayload? { get }
    var onArmingStatusChanged: ((WatchArmingStatus?) -> Void)? { get set }
    var onSessionResultChanged: ((SessionResultPayload?) -> Void)? { get set }
    var onRunLogSummaryChanged: ((RunLogSummaryPayload?) -> Void)? { get set }
    var outboundOutbox: [SmartSleepConnectivityMessage] { get }
    func sendAlarmConfig(_ payload: AlarmConfigPayload)
    func cancelAlarm(id: UUID)
}
```

在 `FakePhoneConnectivityClient` 增加对应属性和方法：

```swift
private(set) var lastSessionResult: SessionResultPayload?
private(set) var lastRunLogSummary: RunLogSummaryPayload?
var onSessionResultChanged: ((SessionResultPayload?) -> Void)?
var onRunLogSummaryChanged: ((RunLogSummaryPayload?) -> Void)?

func deliverSessionResult(_ payload: SessionResultPayload) {
    lastSessionResult = payload
    onSessionResultChanged?(payload)
}

func deliverRunLogSummary(_ payload: RunLogSummaryPayload) {
    lastRunLogSummary = payload
    onRunLogSummaryChanged?(payload)
}
```

在 `IOSConnectivityService.receive(_:)` 改为 switch：

```swift
switch message {
case let .armingResult(payload):
    lastArmingStatus = payload.status
    onArmingStatusChanged?(payload.status)
case let .sessionResult(payload):
    lastSessionResult = payload
    onSessionResultChanged?(payload)
case let .runLogSummary(payload):
    lastRunLogSummary = payload
    onRunLogSummaryChanged?(payload)
case .alarmConfig, .alarmCancelled:
    break
}
```

- [ ] **Step 3: AppModel 分离保存 session result**

在 `AlarmDashboardModel` 增加：

```swift
private var sessionResults: [UUID: SessionResultPayload] = [:]
private var runSummaries: [UUID: RunLogSummaryPayload] = [:]
```

初始化中注册回调：

```swift
self.connectivity.onSessionResultChanged = { [weak self] payload in
    Task { @MainActor in self?.applySessionResult(payload) }
}
self.connectivity.onRunLogSummaryChanged = { [weak self] payload in
    Task { @MainActor in self?.applyRunLogSummary(payload) }
}
applySessionResult(connectivity.lastSessionResult)
applyRunLogSummary(connectivity.lastRunLogSummary)
```

新增方法：

```swift
private func applySessionResult(_ payload: SessionResultPayload?) {
    guard let payload else { return }
    sessionResults[payload.alarmId] = payload
    guard let index = alarms.firstIndex(where: { $0.id == payload.alarmId }) else { return }
    alarms[index].sessionResult = payload
    if payload.failureReason != nil || payload.state == .fallbackPhoneAlarm {
        userVisibleWarning = "Watch runtime unavailable; iPhone fallback is active. \(payload.failureReason ?? "unknown_runtime_failure")"
    }
}

private func applyRunLogSummary(_ payload: RunLogSummaryPayload?) {
    guard let payload else { return }
    runSummaries[payload.runId] = payload
}
```

`reload()` 映射时传入 `sessionResults[alarm.id]`。

- [ ] **Step 4: AlarmCardState 合并状态**

在 `AlarmCardState` 增加：

```swift
var sessionResult: SessionResultPayload?

var smartStatus: SmartModeStatus {
    if let sessionResult,
       sessionResult.failureReason != nil || sessionResult.state == .fallbackPhoneAlarm {
        return .fallbackOnly
    }
    return SmartModeResolver.status(for: alarm, arming: armingStatus)
}
```

更新 `from(...)` 和 `make(...)` 保持 `sessionResult` 默认 `nil`。

- [ ] **Step 5: 验证**

Run with XcodeBuildMCP against the `SmartSleepAlarm` scheme on an available iOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,id=FD770DCA-02E9-4FE8-A924-2AC0C699A2DE'
```

Expected: PASS, 0 failures.

## Task 2: Watch Logger 提供真实 Event Count

**Files:**
- Modify: `Apps/Watch/Sources/WatchAlarmRunLogger.swift`
- Test: `Apps/Watch/Tests/WatchAlarmRunLoggerTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WatchAlarmRunLoggerTests` 增加：

```swift
func testLoggerCountsExportedEventsForRun() throws {
    let logger = try WatchAlarmRunLogger(logsDirectory: temporaryDirectoryURL())
    let runId = UUID()

    try logger.recordRuntimeSession(RuntimeSessionLog(
        runId: runId,
        sessionType: "smartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 10),
        actualStartAt: Date(timeIntervalSince1970: 11),
        invalidatedAt: nil,
        invalidationReason: nil,
        startLatencySec: 1,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: nil,
        errorMessage: nil
    ))
    try logger.recordFreshness(SensorFreshness.fixture(
        motionLastSampleAgeSec: 1,
        hrLastSampleAgeSec: nil,
        baselineHRConfidence: .none,
        watchWornConfidence: .medium
    ))

    XCTAssertEqual(try logger.eventCount(runId: runId), 2)
}
```

Expected: FAIL because `eventCount(runId:)` does not exist.

- [ ] **Step 2: 扩展 logger 协议和 fake**

在 `WatchAlarmRunLogging` 增加：

```swift
func eventCount(runId: UUID) throws -> Int
```

真实 logger：

```swift
func eventCount(runId: UUID) throws -> Int {
    let store = try JSONLAlarmEventStore(directory: logsDirectory)
    return try store.export(runId: runId).count
}
```

fake logger：

```swift
func eventCount(runId: UUID) throws -> Int {
    stateTransitionLogs.filter { $0.runId == runId }.count
        + runtimeLogs.filter { $0.runId == runId }.count
        + channelLogs.filter { $0.runId == runId }.count
        + freshnessLogs.filter { $0.runId == runId }.count
        + gestureLogs.filter { $0.runId == runId }.count
        + outcomeLogs.filter { $0.runId == runId }.count
}
```

- [ ] **Step 3: 验证**

Run with XcodeBuildMCP against the `SmartSleepWatch` scheme on an available watchOS Simulator returned by `list_sims(enabled: true)`. On the current machine, `list_sims(enabled: true)` includes `Apple Watch Series 10 (46mm)` with simulatorId `2AC7F432-233D-42C0-8F88-9041EE6CE231`, so the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
```

Expected: PASS, 0 failures.

## Task 3: Watch 发送 Run Summary

**Files:**
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Test: `Apps/Watch/Tests/WatchAppModelTests.swift`

- [ ] **Step 1: 写失败测试**

在 `WatchAppModelTests` 增加：

```swift
func testStopAfterRuntimeRunSendsRunLogSummaryWithLoggerEventCount() {
    let alarm = Alarm.fixture(smartEnabled: true)
    let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSince1970: 3_600))
    let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
    let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
    let logger = FakeWatchAlarmRunLogger()
    let model = WatchAppModel(
        connectivity: connectivity,
        runtimeScheduler: runtimeScheduler,
        ringer: FakeWatchAlarmRinger(),
        runLogger: logger
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
    model.stop()

    let summaries = connectivity.outboundMessages.compactMap { message -> RunLogSummaryPayload? in
        guard case let .runLogSummary(payload) = message else { return nil }
        return payload
    }
    let summary = try! XCTUnwrap(summaries.last)
    XCTAssertEqual(summary.runId, runId)
    XCTAssertEqual(summary.finalState, .completed)
    XCTAssertEqual(summary.outcome, .userStopped)
    XCTAssertEqual(summary.eventCount, try logger.eventCount(runId: runId))
}
```

Expected: FAIL because `WatchAppModel.stop()` does not send a run summary.

- [ ] **Step 2: 写 runtime failure summary 失败测试**

在 `WatchAppModelTests` 增加：

```swift
func testRuntimeInvalidationSendsRunLogSummaryWithFallbackUsed() {
    let alarm = Alarm.fixture(smartEnabled: true)
    let payload = AlarmConfigPayload(alarm: alarm, nextFireAt: Date(timeIntervalSince1970: 3_600))
    let connectivity = FakeWatchConnectivityClient(latestAlarmConfig: payload)
    let runtimeScheduler = FakeRuntimeSessionScheduler(shouldSucceed: true)
    let logger = FakeWatchAlarmRunLogger()
    let model = WatchAppModel(
        connectivity: connectivity,
        runtimeScheduler: runtimeScheduler,
        ringer: FakeWatchAlarmRinger(),
        runLogger: logger
    )

    model.armCurrentAlarm()
    let runId = try! XCTUnwrap(runtimeScheduler.lastRunID)
    runtimeScheduler.emitInvalidation(RuntimeSessionLog(
        runId: runId,
        sessionType: "fakeSmartAlarmPreMonitoring",
        scheduledAt: Date(timeIntervalSince1970: 0),
        targetStartAt: Date(timeIntervalSince1970: 0),
        actualStartAt: Date(timeIntervalSince1970: 10),
        invalidatedAt: Date(timeIntervalSince1970: 20),
        invalidationReason: "expired",
        startLatencySec: 10,
        didStartBeforeAlarm: true,
        didReachRingTime: false,
        errorCode: "runtime_session_invalidated",
        errorMessage: "expired"
    ))

    let summaries = connectivity.outboundMessages.compactMap { message -> RunLogSummaryPayload? in
        guard case let .runLogSummary(payload) = message else { return nil }
        return payload
    }
    let summary = try! XCTUnwrap(summaries.last)
    XCTAssertEqual(summary.runId, runId)
    XCTAssertEqual(summary.finalState, .fallbackPhoneAlarm)
    XCTAssertNil(summary.outcome)
    XCTAssertEqual(summary.fallbackUsed, true)
    XCTAssertEqual(summary.eventCount, try logger.eventCount(runId: runId))
}
```

Expected: FAIL because `handleRuntimeLogUpdate(_:)` does not send a run summary.

- [ ] **Step 3: 实现 summary 发送**

在 `WatchAppModel` 增加 helper：

```swift
private func sendRunSummary(outcome: OutcomeKind?, fallbackUsed: Bool = false) {
    guard let activeRunID else { return }
    let count = (try? runLogger.eventCount(runId: activeRunID)) ?? 0
    connectivity.sendRunLogSummary(RunLogSummaryPayload(
        runId: activeRunID,
        finalState: currentState,
        outcome: outcome,
        eventCount: count,
        fallbackUsed: fallbackUsed
    ))
}
```

在 `stop()` 成功更新 `currentState` 后调用：

```swift
sendRunSummary(outcome: .userStopped)
```

在 `snooze()` 成功更新 `currentState` 后调用：

```swift
sendRunSummary(outcome: .userSnoozed)
```

在 `handleRuntimeLogUpdate(_:)` 发送 `SessionResultPayload` 后调用：

```swift
sendRunSummary(outcome: nil, fallbackUsed: true)
```

在 `handleConfigChange(_:)` 取消已预约 runtime 前，如 `activeRunID != nil`，先把当前状态转为 `.fallbackPhoneAlarm` 或 `.needsWatchArming` 后发送 summary：

```swift
if activeRunID != nil {
    sendRunSummary(outcome: nil, fallbackUsed: currentState == .fallbackPhoneAlarm)
}
```

不要在 `sendRunSummary` 中估算事件数；只能调用 `runLogger.eventCount(runId:)`。

- [ ] **Step 4: iOS 展示 run summary**

在 `AlarmDashboardModel` 保留按 runId 的事实源，并额外暴露 latest 给内部调试区：

```swift
private var runSummaries: [UUID: RunLogSummaryPayload] = [:]
@Published private(set) var latestRunSummary: RunLogSummaryPayload?
```

`applyRunLogSummary(_:)` 中必须同时保存按 runId 的映射和 latest：

```swift
private func applyRunLogSummary(_ payload: RunLogSummaryPayload?) {
    guard let payload else { return }
    runSummaries[payload.runId] = payload
    latestRunSummary = payload
}
```

增加多 run 防覆盖测试：

```swift
func testModelStoresRunSummariesByRunIdAndOnlyUsesLatestForDebugDisplay() async throws {
    let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
    let connectivity = FakePhoneConnectivityClient()
    let model = AlarmDashboardModel(
        repository: repository,
        notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
        backupScheduler: RecordingBackupAlarmScheduler(),
        connectivity: connectivity,
        runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
    )
    let firstRunId = UUID()
    let secondRunId = UUID()

    connectivity.deliverRunLogSummary(RunLogSummaryPayload(
        runId: firstRunId,
        finalState: .completed,
        outcome: .userStopped,
        eventCount: 4,
        fallbackUsed: false
    ))
    connectivity.deliverRunLogSummary(RunLogSummaryPayload(
        runId: secondRunId,
        finalState: .fallbackPhoneAlarm,
        outcome: nil,
        eventCount: 6,
        fallbackUsed: true
    ))
    await flushMainActorWork()

    XCTAssertEqual(model.latestRunSummary?.runId, secondRunId)
    XCTAssertEqual(model.latestRunSummary?.eventCount, 6)
}
```

在 `SmartSleepAlarmApp.swift` 内部测试区只显示 `latestRunSummary.finalState`、`outcome`、`eventCount`，不要把 latest summary 当作卡片状态事实源；卡片状态仍来自 alarm 对应的 `sessionResult`。

- [ ] **Step 5: 验证**

Run with XcodeBuildMCP against the `SmartSleepWatch` and `SmartSleepAlarm` schemes on available simulators returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell commands are:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,id=2AC7F432-233D-42C0-8F88-9041EE6CE231'
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,id=FD770DCA-02E9-4FE8-A924-2AC0C699A2DE'
```

Expected: both PASS, 0 failures.

## Task 4: Compile-Gated AlarmKit Capability Prep

**Files:**
- Modify: `Apps/iOS/Sources/AppModel.swift`
- Modify: `Apps/iOS/Sources/AlarmKitBackupAlarmScheduler.swift`
- Modify: `Apps/iOS/Tests/BackupAlarmSchedulerTests.swift`
- Modify: `docs/qa/device-test-matrix.md`

- [ ] **Step 1: 写 capability provider 测试**

在 `AlarmDashboardModelTests` 增加：

```swift
func testAlarmKitCapabilityProviderAllowsAlarmKitFallbackWhenSupportedAndAuthorized() async throws {
    let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
    let scheduler = RecordingBackupAlarmScheduler(recordedChannel: .iOSAlarmKit)
    let model = AlarmDashboardModel(
        repository: repository,
        notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
        backupScheduler: scheduler,
        connectivity: FakePhoneConnectivityClient(),
        runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true)),
        alarmKitCapabilityProvider: FakeAlarmKitCapabilityProvider(isSupported: true, authorization: .authorized)
    )
    var alarm = AlarmCardState.make(
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        label: "AlarmKit",
        smartEnabled: true,
        snoozeMinutes: 9
    )
    alarm.alarm.backupChannelPreferred = .iOSAlarmKit
    alarm.armingStatus = WatchArmingStatus(
        alarmId: alarm.id,
        isArmed: false,
        sessionScheduled: false,
        fallbackChannel: .iOSAlarmKit,
        failureReason: "watch_not_armed"
    )

    await model.refreshNotificationAuthorization()
    model.create(alarm)
    await flushMainActorWork()

    XCTAssertEqual(scheduler.scheduledChannels.last, .iOSAlarmKit)
}

func testDisabledAlarmKitProviderFallsBackToLocalNotification() async throws {
    let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
    let scheduler = RecordingBackupAlarmScheduler(recordedChannel: .iOSLocalNotification)
    let model = AlarmDashboardModel(
        repository: repository,
        notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
        backupScheduler: scheduler,
        connectivity: FakePhoneConnectivityClient(),
        runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true)),
        alarmKitCapabilityProvider: FakeAlarmKitCapabilityProvider(isSupported: false, authorization: .unavailable)
    )
    let alarm = AlarmCardState.make(
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        label: "Local",
        smartEnabled: false,
        snoozeMinutes: 9
    )

    await model.refreshNotificationAuthorization()
    model.create(alarm)
    await flushMainActorWork()

    XCTAssertEqual(scheduler.scheduledChannels.last, .iOSLocalNotification)
}
```

Expected: FAIL because `AlarmDashboardModel` has no `alarmKitCapabilityProvider` injection and `RecordingBackupAlarmScheduler` may need `scheduledChannels` tracking.

- [ ] **Step 2: 增加协议**

```swift
protocol AlarmKitCapabilityProviding {
    var isAlarmKitSupported: Bool { get }
    func authorizationState() async -> AuthorizationState
}

struct DisabledAlarmKitCapabilityProvider: AlarmKitCapabilityProviding {
    var isAlarmKitSupported: Bool { false }
    func authorizationState() async -> AuthorizationState { .unavailable }
}
```

在 `AlarmDashboardModel` 增加属性：

```swift
private let alarmKitCapabilityProvider: AlarmKitCapabilityProviding
```

把 init 签名扩展为：

```swift
init(
    repository: AlarmRepository,
    notificationAuthorizer: NotificationAuthorizing = NotificationPermissionService(),
    backupScheduler: BackupAlarmScheduling = RoutingBackupAlarmScheduler(),
    connectivity: PhoneConnectivityClient = IOSConnectivityService(),
    runLogger: AlarmRunLogging = AlarmRunLogger.temporary(),
    alarmKitCapabilityProvider: AlarmKitCapabilityProviding = DisabledAlarmKitCapabilityProvider()
)
```

新增参数：

```swift
alarmKitCapabilityProvider: AlarmKitCapabilityProviding = DisabledAlarmKitCapabilityProvider()
```

init body 中赋值：

```swift
self.alarmKitCapabilityProvider = alarmKitCapabilityProvider
```

在 `scheduleFallbackIfNeeded(for:runId:)` 中替换当前 `alarmKitSupported: false` 硬编码：

```swift
let alarmKitAuthorization = await alarmKitCapabilityProvider.authorizationState()
let capabilities = BackupChannelCapabilities(
    alarmKitSupported: alarmKitCapabilityProvider.isAlarmKitSupported,
    alarmKitAuthorization: alarmKitAuthorization,
    notificationAuthorization: authorizationState,
    foregroundAudioAvailable: false
)
```

在 `RecordingBackupAlarmScheduler` 增加测试可见的 channel 记录：

```swift
private(set) var scheduledChannels: [AlarmChannel] = []
```

在 `scheduleBackup(...)` 成功分支中记录：

```swift
scheduledAlarmIDs.append(alarm.id)
scheduledChannels.append(requiredChannel)
```

在 `AlarmDashboardModelTests` 增加 fake provider：

```swift
struct FakeAlarmKitCapabilityProvider: AlarmKitCapabilityProviding {
    var isSupported: Bool
    var authorization: AuthorizationState

    var isAlarmKitSupported: Bool { isSupported }
    func authorizationState() async -> AuthorizationState { authorization }
}
```

- [ ] **Step 3: 保持真实 API 为独立 spike**

`AlarmKitBackupAlarmScheduler` 本阶段只保留 compile-gated stub，不在未核验 API 签名前硬写真实 schedule 调用。更新 `docs/qa/device-test-matrix.md` 的 AlarmKit 条目为：真实 API 接入需单独查当前官方 SDK/文档，真机验证授权、schedule、stop/snooze 日志。

- [ ] **Step 4: 验证**

Run with XcodeBuildMCP against the `SmartSleepAlarm` scheme on an available iOS Simulator returned by `list_sims(enabled: true)`. On the current machine, the equivalent shell command is:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,id=FD770DCA-02E9-4FE8-A924-2AC0C699A2DE'
```

Expected: PASS, 0 failures.

## Final Verification

- [ ] `git diff` 只包含本计划相关源码、测试和文档。
- [ ] `swift test --package-path Packages/SmartSleepCore` 通过。
- [ ] `SmartSleepAlarm` scheme 测试通过。
- [ ] `SmartSleepWatch` scheme 测试通过。
- [ ] XcodeBuildMCP `list_schemes` 仍显示 `SmartSleepAlarm`、`SmartSleepCore`、`SmartSleepWatch`。

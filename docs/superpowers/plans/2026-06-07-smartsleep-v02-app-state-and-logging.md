# SmartSleep v0.2 App State and Logging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iPhone MVP durable and inspectable by adding persisted alarms, deterministic scheduling policy, local run/channel logs, JSONL export, and conservative feature flags.

**Architecture:** Keep this plan free of real Apple device APIs other than local file access and SwiftUI wiring. `SmartSleepCore` owns pure Swift contracts, policies, state transitions, and tests. The iOS app target owns file persistence and UI state mapping, with protocol injection points ready for later device adapters.

**Tech Stack:** Swift 6.1, Swift Package Manager, SwiftUI, XcodeGen, XCTest, JSONL local files, XcodeBuildMCP for Simulator build/run checks.

---

## Scope

This plan implements `v02-app-state-and-logging` only:

- iPhone alarm repository contract.
- File-backed iPhone alarm persistence.
- UI model that loads from disk and refreshes after create/delete.
- Pure scheduling policy that records fallback intent as `.iOSLocalNotification`.
- `AlarmRunCoordinator` that writes state transitions and `AlarmChannelLog` entries.
- Export service for JSONL run logs.
- v0.2 feature flags.

This plan does not implement real `WCSession`, real `UNUserNotificationCenter` scheduling, AlarmKit, Watch runtime sessions, Watch haptics/audio, or real-device matrices. Those are in `docs/superpowers/plans/2026-06-07-smartsleep-v02-device-integration-spikes.md`.

## File Structure

```text
Packages/SmartSleepCore/
  Sources/SmartSleepCore/
    AlarmRepository.swift
    AlarmSchedulerPolicy.swift
    AlarmRunCoordinator.swift
    FeatureFlags.swift
  Tests/SmartSleepCoreTests/
    AlarmRepositoryTests.swift
    AlarmSchedulerPolicyTests.swift
    AlarmRunCoordinatorTests.swift
    FeatureFlagsTests.swift

Apps/iOS/Sources/
  SmartSleepAlarmApp.swift
  AppModel.swift
  AlarmFileRepositoryAdapter.swift
  LogExportService.swift

docs/qa/
  dogfood-runbook.md
```

## Task 1: Verify Current Baseline

**Files:**
- Existing: `Packages/SmartSleepCore`
- Existing: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`
- Existing: `project.yml`

- [ ] **Step 1: Inspect status**

Run:

```bash
git status --short
```

Expected: source and docs changes are intentional. No `.build/`, `DerivedData/`, `.xcuserdata/`, or simulator logs are listed.

- [ ] **Step 2: Run core tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: existing XCTest suites pass with 0 failures.

- [ ] **Step 3: Regenerate project and build iOS**

Run:

```bash
xcodegen generate
```

Use XcodeBuildMCP. Before the first build call in the session, run `session_show_defaults()`.

```text
session_set_defaults(
  projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj",
  scheme: "SmartSleepAlarm",
  simulatorName: "iPhone 16 Pro",
  simulatorPlatform: "iOS Simulator",
  configuration: "Debug",
  derivedDataPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/.build/DerivedData",
  useLatestOS: true,
  bundleId: "com.smartsleep.alarm"
)
build_sim()
```

Expected: project generation succeeds and iOS build returns `SUCCEEDED`.

- [ ] **Step 4: Commit baseline if needed**

Run:

```bash
git add .gitignore AGENTS.md Apps Packages README.md docs project.yml
git commit -m "chore: establish smartsleep v02 baseline"
```

Expected: baseline changes are committed. If the branch already has this baseline commit, skip this commit step.

## Task 2: Add Pure Swift Alarm Repository

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRepository.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRepositoryTests.swift`

- [ ] **Step 1: Write failing repository tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRepositoryTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class AlarmRepositoryTests: XCTestCase {
    func testMemoryRepositoryCreatesListsUpdatesAndDeletesAlarms() throws {
        let repository = MemoryAlarmRepository()
        let alarm = Alarm.fixture(smartEnabled: true)

        try repository.save(alarm)
        XCTAssertEqual(try repository.list(), [alarm])

        var disabled = alarm
        disabled.isEnabled = false
        try repository.save(disabled)
        XCTAssertEqual(try repository.alarm(id: alarm.id)?.isEnabled, false)

        try repository.delete(id: alarm.id)
        XCTAssertEqual(try repository.list(), [])
    }

    func testMemoryRepositorySortsByTimeOfDay() throws {
        let repository = MemoryAlarmRepository()
        var later = Alarm.fixture(smartEnabled: true)
        later.timeOfDay = DateComponents(hour: 8, minute: 15)

        var earlier = Alarm.fixture(smartEnabled: true)
        earlier.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        earlier.timeOfDay = DateComponents(hour: 6, minute: 45)

        try repository.save(later)
        try repository.save(earlier)

        XCTAssertEqual(try repository.list().map(\.id), [earlier.id, later.id])
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmRepositoryTests
```

Expected: compile failure says `cannot find 'MemoryAlarmRepository' in scope`.

- [ ] **Step 3: Implement repository contract**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRepository.swift`:

```swift
import Foundation

public protocol AlarmRepository: Sendable {
    func list() throws -> [Alarm]
    func alarm(id: UUID) throws -> Alarm?
    func save(_ alarm: Alarm) throws
    func delete(id: UUID) throws
}

public final class MemoryAlarmRepository: AlarmRepository, @unchecked Sendable {
    private var storage: [UUID: Alarm]

    public init(alarms: [Alarm] = []) {
        self.storage = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
    }

    public func list() throws -> [Alarm] {
        storage.values.sorted { lhs, rhs in
            let lhsHour = lhs.timeOfDay.hour ?? 0
            let rhsHour = rhs.timeOfDay.hour ?? 0
            if lhsHour != rhsHour { return lhsHour < rhsHour }
            return (lhs.timeOfDay.minute ?? 0) < (rhs.timeOfDay.minute ?? 0)
        }
    }

    public func alarm(id: UUID) throws -> Alarm? {
        storage[id]
    }

    public func save(_ alarm: Alarm) throws {
        storage[alarm.id] = alarm
    }

    public func delete(id: UUID) throws {
        storage.removeValue(forKey: id)
    }
}
```

- [ ] **Step 4: Run repository tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmRepositoryTests
```

Expected: `AlarmRepositoryTests` passes with 0 failures.

- [ ] **Step 5: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRepository.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRepositoryTests.swift
git commit -m "feat: add alarm repository contract"
```

## Task 3: Persist iPhone Alarms and Load UI From Disk

**Files:**
- Create: `Apps/iOS/Sources/AlarmFileRepositoryAdapter.swift`
- Create: `Apps/iOS/Sources/AppModel.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`

- [ ] **Step 1: Add UI presentation mapper**

Modify `Apps/iOS/Sources/SmartSleepAlarmApp.swift` by changing `private struct AlarmCardState` to:

```swift
struct AlarmCardState: Identifiable, Equatable {
```

Then add this extension below `AlarmCardState`:

```swift
extension AlarmCardState {
    static func from(
        alarm: Alarm,
        armingStatus: WatchArmingStatus? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> AlarmCardState {
        let hour = alarm.timeOfDay.hour ?? 7
        let minute = alarm.timeOfDay.minute ?? 30
        let base = calendar.startOfDay(for: now)
        let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? now
        let nextFireAt = candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        return AlarmCardState(id: alarm.id, alarm: alarm, armingStatus: armingStatus, nextFireAt: nextFireAt)
    }
}
```

- [ ] **Step 2: Create file repository adapter**

Create `Apps/iOS/Sources/AlarmFileRepositoryAdapter.swift`:

```swift
import Foundation
import SmartSleepCore

final class AlarmFileRepositoryAdapter: AlarmRepository, @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func list() throws -> [Alarm] {
        try readAll().sorted { lhs, rhs in
            let lhsHour = lhs.timeOfDay.hour ?? 0
            let rhsHour = rhs.timeOfDay.hour ?? 0
            if lhsHour != rhsHour { return lhsHour < rhsHour }
            return (lhs.timeOfDay.minute ?? 0) < (rhs.timeOfDay.minute ?? 0)
        }
    }

    func alarm(id: UUID) throws -> Alarm? {
        try readAll().first { $0.id == id }
    }

    func save(_ alarm: Alarm) throws {
        var alarms = try readAll()
        alarms.removeAll { $0.id == alarm.id }
        alarms.append(alarm)
        try writeAll(alarms)
    }

    func delete(id: UUID) throws {
        var alarms = try readAll()
        alarms.removeAll { $0.id == id }
        try writeAll(alarms)
    }

    private func readAll() throws -> [Alarm] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Alarm].self, from: data)
    }

    private func writeAll(_ alarms: [Alarm]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(alarms)
        try data.write(to: fileURL, options: .atomic)
    }

    static func appStorage() throws -> AlarmFileRepositoryAdapter {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return AlarmFileRepositoryAdapter(fileURL: documents.appendingPathComponent("alarms.json"))
    }
}
```

- [ ] **Step 3: Create app model**

Create `Apps/iOS/Sources/AppModel.swift`:

```swift
import Foundation
import SmartSleepCore
import SwiftUI

@MainActor
final class AlarmDashboardModel: ObservableObject {
    @Published private(set) var alarms: [AlarmCardState] = []
    @Published var exportedLogText = ""
    @Published var userVisibleWarning: String?

    private let repository: AlarmRepository

    init(repository: AlarmRepository) {
        self.repository = repository
        reload()
    }

    convenience init() {
        do {
            try self.init(repository: AlarmFileRepositoryAdapter.appStorage())
        } catch {
            self.init(repository: MemoryAlarmRepository())
            self.userVisibleWarning = "Alarm storage unavailable; using temporary alarms."
        }
    }

    func reload() {
        do {
            let persisted = try repository.list()
            alarms = persisted.map { AlarmCardState.from(alarm: $0) }
            if alarms.isEmpty {
                alarms = AlarmCardState.seed
                for item in alarms {
                    try repository.save(item.alarm)
                }
            }
        } catch {
            userVisibleWarning = "Failed to load alarms."
        }
    }

    func create(_ alarm: AlarmCardState) {
        do {
            try repository.save(alarm.alarm)
            reload()
        } catch {
            userVisibleWarning = "Failed to save alarm."
            exportedLogText = #"{"error":"failed_to_save_alarm"}"#
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { alarms[$0].id }
        do {
            for id in ids {
                try repository.delete(id: id)
            }
            reload()
        } catch {
            userVisibleWarning = "Failed to delete alarm."
            exportedLogText = #"{"error":"failed_to_delete_alarm"}"#
        }
    }

    func exportPreview() {
        exportedLogText = LogPreviewBuilder.makePreview(for: alarms)
    }
}
```

- [ ] **Step 4: Wire SwiftUI to app model**

Replace `AlarmDashboardView` in `Apps/iOS/Sources/SmartSleepAlarmApp.swift` with:

```swift
private struct AlarmDashboardView: View {
    @StateObject private var model = AlarmDashboardModel()
    @State private var isCreatingAlarm = false

    var body: some View {
        NavigationStack {
            List {
                if let warning = model.userVisibleWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle")
                    }
                }

                Section {
                    ForEach(model.alarms) { alarm in
                        AlarmCard(alarm: alarm)
                    }
                    .onDelete(perform: model.delete)
                }

                Section("内部测试日志") {
                    Button {
                        model.exportPreview()
                    } label: {
                        Label("导出本地 JSON 预览", systemImage: "square.and.arrow.up")
                    }

                    if !model.exportedLogText.isEmpty {
                        Text(model.exportedLogText)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(8)
                    }
                }
            }
            .navigationTitle("SmartSleep")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatingAlarm = true
                    } label: {
                        Label("新增闹铃", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isCreatingAlarm) {
                CreateAlarmView { alarm in
                    model.create(alarm)
                }
            }
        }
    }
}
```

- [ ] **Step 5: Build and launch iOS**

Use XcodeBuildMCP:

```text
build_run_sim()
snapshot_ui()
stop_app_sim()
```

Expected:

- Build succeeds.
- Snapshot contains `SmartSleep`.
- Snapshot contains `导出本地 JSON 预览`.
- Relaunching after create/delete still shows alarms loaded through the repository path.
- `AppModel.swift` can access `AlarmCardState` because `AlarmCardState` is no longer private.

- [ ] **Step 6: Commit**

Run:

```bash
git add Apps/iOS/Sources/AlarmFileRepositoryAdapter.swift Apps/iOS/Sources/AppModel.swift Apps/iOS/Sources/SmartSleepAlarmApp.swift
git commit -m "feat: persist iphone alarms"
```

## Task 4: Add Scheduling Policy and Run Logs

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift`
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRunCoordinator.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmSchedulerPolicyTests.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRunCoordinatorTests.swift`

- [ ] **Step 1: Write failing scheduling policy tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmSchedulerPolicyTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class AlarmSchedulerPolicyTests: XCTestCase {
    func testSmartAlarmWithoutWatchArmingNeedsPhoneBackup() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let decision = AlarmSchedulerPolicy().decision(for: alarm, arming: nil)

        XCTAssertEqual(decision.smartModeStatus, .needsWatchArming)
        XCTAssertTrue(decision.shouldSyncToWatch)
        XCTAssertTrue(decision.shouldSchedulePhoneBackup)
        XCTAssertEqual(decision.requiredBackupChannel, .iOSLocalNotification)
    }

    func testReadySmartAlarmStillKeepsPhoneBackupInV02() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let arming = WatchArmingStatus(
            alarmId: alarm.id,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSLocalNotification,
            failureReason: nil
        )

        let decision = AlarmSchedulerPolicy().decision(for: alarm, arming: arming)

        XCTAssertEqual(decision.smartModeStatus, .ready)
        XCTAssertTrue(decision.shouldSchedulePhoneBackup)
        XCTAssertEqual(decision.requiredBackupChannel, .iOSLocalNotification)
    }
}
```

- [ ] **Step 2: Write failing coordinator tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRunCoordinatorTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class AlarmRunCoordinatorTests: XCTestCase {
    func testCoordinatorLogsStateTransitionsAndChannelEvents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try JSONLAlarmEventStore(directory: directory)
        var coordinator = AlarmRunCoordinator(runId: UUID(), eventStore: store)

        try coordinator.apply(.phoneCreatedAlarm, reason: "created_on_phone")
        try coordinator.appendChannelLog(AlarmChannelLog(
            runId: coordinator.runId,
            channel: .iOSLocalNotification,
            scheduledAt: Date(),
            firedAt: nil,
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: "scheduled"
        ))

        let exported = try store.export(runId: coordinator.runId)
        XCTAssertEqual(exported.count, 2)
        XCTAssertTrue(exported[0].contains("created_on_phone"))
        XCTAssertTrue(exported[1].contains("iOSLocalNotification"))
    }
}
```

- [ ] **Step 3: Run tests to verify failures**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmSchedulerPolicyTests
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmRunCoordinatorTests
```

Expected: compile failures for missing `AlarmSchedulerPolicy` and `AlarmRunCoordinator`.

- [ ] **Step 4: Implement scheduling policy**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift`:

```swift
import Foundation

public struct AlarmSchedulingDecision: Equatable, Sendable {
    public var smartModeStatus: SmartModeStatus
    public var shouldSyncToWatch: Bool
    public var shouldSchedulePhoneBackup: Bool
    public var requiredBackupChannel: AlarmChannel

    public init(
        smartModeStatus: SmartModeStatus,
        shouldSyncToWatch: Bool,
        shouldSchedulePhoneBackup: Bool,
        requiredBackupChannel: AlarmChannel
    ) {
        self.smartModeStatus = smartModeStatus
        self.shouldSyncToWatch = shouldSyncToWatch
        self.shouldSchedulePhoneBackup = shouldSchedulePhoneBackup
        self.requiredBackupChannel = requiredBackupChannel
    }
}

public struct AlarmSchedulerPolicy: Sendable {
    public init() {}

    public func decision(for alarm: Alarm, arming: WatchArmingStatus?) -> AlarmSchedulingDecision {
        let status = SmartModeResolver.status(for: alarm, arming: arming)
        return AlarmSchedulingDecision(
            smartModeStatus: status,
            shouldSyncToWatch: alarm.isEnabled && alarm.smartEnabled,
            shouldSchedulePhoneBackup: alarm.isEnabled,
            requiredBackupChannel: .iOSLocalNotification
        )
    }
}
```

- [ ] **Step 5: Implement run coordinator**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRunCoordinator.swift`:

```swift
import Foundation

public struct AlarmRunCoordinator: Sendable {
    public let runId: UUID
    private var machine: AlarmStateMachine
    private let eventStore: JSONLAlarmEventStore

    public init(
        runId: UUID = UUID(),
        initialState: SmartAlarmState = .idle,
        eventStore: JSONLAlarmEventStore
    ) {
        self.runId = runId
        self.machine = AlarmStateMachine(initialState: initialState)
        self.eventStore = eventStore
    }

    public var state: SmartAlarmState {
        machine.state
    }

    public mutating func apply(
        _ event: SmartAlarmEvent,
        reason: String,
        confidence: Double? = nil,
        featureSnapshotId: String? = nil,
        errorCode: String? = nil,
        timestamp: Date = Date()
    ) throws {
        let from = machine.state
        try machine.apply(event)
        let log = StateTransitionLog(
            runId: runId,
            fromState: from,
            toState: machine.state,
            timestamp: timestamp,
            reason: reason,
            confidence: confidence,
            featureSnapshotId: featureSnapshotId,
            errorCode: errorCode
        )
        try eventStore.append(.stateTransition(log), recordedAt: timestamp)
    }

    public func appendChannelLog(_ log: AlarmChannelLog, timestamp: Date = Date()) throws {
        try eventStore.append(.alarmChannel(log), recordedAt: timestamp)
    }
}
```

- [ ] **Step 6: Run tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmSchedulerPolicyTests
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmRunCoordinatorTests
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all listed tests pass with 0 failures.

- [ ] **Step 7: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRunCoordinator.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmSchedulerPolicyTests.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRunCoordinatorTests.swift
git commit -m "feat: add alarm scheduling logs"
```

## Task 5: Add JSONL Export Service and Feature Flags

**Files:**
- Create: `Apps/iOS/Sources/LogExportService.swift`
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/FeatureFlags.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/FeatureFlagsTests.swift`
- Modify: `docs/qa/dogfood-runbook.md`

- [ ] **Step 1: Create export service**

Create `Apps/iOS/Sources/LogExportService.swift`:

```swift
import Foundation
import SmartSleepCore

protocol AlarmRunExporting {
    func export(runId: UUID) throws -> String
}

struct LogExportService: AlarmRunExporting {
    private let logsDirectory: URL

    init(logsDirectory: URL) {
        self.logsDirectory = logsDirectory
    }

    func export(runId: UUID) throws -> String {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        return try store.export(runId: runId).joined(separator: "\n")
    }

    static func appStorage() throws -> LogExportService {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return LogExportService(logsDirectory: documents.appendingPathComponent("AlarmRuns", isDirectory: true))
    }
}
```

- [ ] **Step 2: Write failing feature flag tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/FeatureFlagsTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class FeatureFlagsTests: XCTestCase {
    func testDefaultFlagsKeepExperimentalBehaviorConservative() {
        let flags = FeatureFlags.v02Default

        XCTAssertFalse(flags.autoSilenceEnabled)
        XCTAssertFalse(flags.reSleepDetectionEnabled)
        XCTAssertTrue(flags.gestureSnoozeEnabled)
        XCTAssertTrue(flags.heartRateBoostEnabled)
        XCTAssertEqual(flags.maxReAlarmCount, 2)
    }
}
```

- [ ] **Step 3: Run feature flag test to verify failure**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter FeatureFlagsTests
```

Expected: compile failure says `cannot find 'FeatureFlags' in scope`.

- [ ] **Step 4: Implement feature flags**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/FeatureFlags.swift`:

```swift
import Foundation

public struct FeatureFlags: Codable, Equatable, Sendable {
    public var autoSilenceEnabled: Bool
    public var reSleepDetectionEnabled: Bool
    public var gestureSnoozeEnabled: Bool
    public var heartRateBoostEnabled: Bool
    public var maxReAlarmCount: Int

    public init(
        autoSilenceEnabled: Bool,
        reSleepDetectionEnabled: Bool,
        gestureSnoozeEnabled: Bool,
        heartRateBoostEnabled: Bool,
        maxReAlarmCount: Int
    ) {
        self.autoSilenceEnabled = autoSilenceEnabled
        self.reSleepDetectionEnabled = reSleepDetectionEnabled
        self.gestureSnoozeEnabled = gestureSnoozeEnabled
        self.heartRateBoostEnabled = heartRateBoostEnabled
        self.maxReAlarmCount = maxReAlarmCount
    }

    public static let v02Default = FeatureFlags(
        autoSilenceEnabled: false,
        reSleepDetectionEnabled: false,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
}
```

- [ ] **Step 5: Update dogfood runbook**

Append to `docs/qa/dogfood-runbook.md`:

```markdown
## Feature Flags

v0.2 default flags:

- `autoSilenceEnabled = false`
- `reSleepDetectionEnabled = false`
- `gestureSnoozeEnabled = true`
- `heartRateBoostEnabled = true`
- `maxReAlarmCount = 2`

Auto silence and re-sleep detection can only be enabled for named internal test runs with exported logs.
```

- [ ] **Step 6: Run tests and build iOS**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm`.

Expected:

- All core tests pass.
- iOS build succeeds.
- `LogExportService.swift` compiles.

- [ ] **Step 7: Commit**

Run:

```bash
git add Apps/iOS/Sources/LogExportService.swift Packages/SmartSleepCore/Sources/SmartSleepCore/FeatureFlags.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/FeatureFlagsTests.swift docs/qa/dogfood-runbook.md
git commit -m "feat: add v02 logs and flags"
```

## Task 6: Final Verification for App State and Logging

**Files:**
- Existing: all files modified by this plan

- [ ] **Step 1: Scan this plan for red flags**

Run:

```bash
rg -n "T[B]D|T[O]DO|impl[e]ment later|fill in d[e]tails|appropriate error h[a]ndling|handle edge c[a]ses|Similar t[o]" docs/superpowers/plans/2026-06-07-smartsleep-v02-app-state-and-logging.md
```

Expected: no matches.

- [ ] **Step 2: Run all tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all XCTest suites pass with 0 failures.

- [ ] **Step 3: Regenerate and build**

Run:

```bash
xcodegen generate
```

Use XcodeBuildMCP:

```text
session_set_defaults(
  projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj",
  scheme: "SmartSleepAlarm",
  simulatorName: "iPhone 16 Pro",
  simulatorPlatform: "iOS Simulator",
  configuration: "Debug",
  derivedDataPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/.build/DerivedData",
  useLatestOS: true,
  bundleId: "com.smartsleep.alarm"
)
build_run_sim()
snapshot_ui()
stop_app_sim()
```

Expected:

- Project generation succeeds.
- Build result is `SUCCEEDED`.
- Snapshot contains `SmartSleep`.
- Snapshot contains `导出本地 JSON 预览`.
- At least one alarm card is visible.

- [ ] **Step 4: Inspect git status**

Run:

```bash
git status --short
```

Expected: no generated artifacts are listed. Only intentional source and docs changes remain if commits were skipped.

## Self-Review

Spec coverage:

- iPhone alarm CRUD and persistence: Tasks 2 and 3.
- Fallback intent as traceable policy: Task 4.
- State transition and channel logs: Task 4.
- Local JSONL export foundation: Task 5.
- Feature flags: Task 5.

Known remaining work:

- Real notification scheduling and permission prompts.
- iOS + Watch target embedding.
- `WCSession` integration.
- Watch runtime session scheduling.
- Watch haptic/audio adapter.
- Real-device matrix execution.

Execution handoff:

- Complete this plan before starting `docs/superpowers/plans/2026-06-07-smartsleep-v02-device-integration-spikes.md`.
- Each P0 task must end with tests, an iOS build when app code changed, and a visible or exported log event when logging behavior changed.

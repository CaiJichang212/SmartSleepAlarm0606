# SmartSleep v0.2 Next Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the current v0.2 shell into a device-testable vertical slice: persisted iPhone alarms, real iPhone-Watch message flow, Watch arming/runtime scheduling hooks, fallback channel logging, and exportable AlarmRun JSONL.

**Architecture:** Keep `SmartSleepCore` as the pure Swift contract layer for models, state transitions, repositories, payloads, and testable policies. Put Apple framework adapters in app targets: iOS owns alarm CRUD, backup scheduling, log export, and `WCSession` receiving; watchOS owns arming, runtime-session scheduling, ringing controls, and `WCSession` replies. Every Apple API adapter must sit behind a small protocol so Simulator/unit tests can exercise policy without pretending to prove real device reliability.

**Tech Stack:** Swift 6.1, Swift Package Manager, SwiftUI, XcodeGen, XCTest, WatchConnectivity, UserNotifications, WatchKit `WKExtendedRuntimeSession`, XcodeBuildMCP for Simulator build/run checks, and manual real-device Spike matrices in `docs/spikes/`.

---

## Current Baseline

The repository already contains:

- `Packages/SmartSleepCore`: pure Swift models, state machine, awake scorer, gesture detector, JSONL event store, connectivity payloads, and tests.
- `Apps/iOS/Sources/SmartSleepAlarmApp.swift`: iOS SwiftUI shell with seeded alarms and status badges.
- `Apps/Watch/Sources/SmartSleepWatchApp.swift`: Watch SwiftUI shell with arming and simulated ringing controls.
- `project.yml`: XcodeGen project config for `SmartSleepAlarm`, `SmartSleepWatch`, and `SmartSleepCore`.
- `docs/prd/SmartSleep_Alarm_v0.2.md`: source-of-truth PRD.
- `docs/spikes/Spike-A-watch-runtime-session.md` through `Spike-F-privacy-review.md`: device spike matrices.

## File Structure Target

Create or modify these files during this integration phase:

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

Apps/iOS/Sources/
  SmartSleepAlarmApp.swift
  AppModel.swift
  AlarmFileRepositoryAdapter.swift
  IOSConnectivityService.swift
  BackupAlarmScheduler.swift
  NotificationPermissionService.swift
  LogExportService.swift

Apps/Watch/Sources/
  SmartSleepWatchApp.swift
  WatchAppModel.swift
  WatchConnectivityService.swift
  WatchRuntimeSessionScheduler.swift
  WatchAlarmRinger.swift

docs/spikes/
  Spike-A-watch-runtime-session.md
  Spike-B-alarm-channel-reliability.md

docs/qa/
  device-test-matrix.md
  dogfood-runbook.md

project.yml
```

## Task 1: Commit the Current Verified Baseline

**Files:**
- Existing: all current project files

- [ ] **Step 1: Inspect current status**

Run:

```bash
git status --short
```

Expected: new project files are visible and there are no generated `.build/` artifacts listed.

- [ ] **Step 2: Run core tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 3: Build iOS target**

Use XcodeBuildMCP:

```text
session_set_defaults(
  projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj",
  scheme: "SmartSleepAlarm",
  simulatorName: "iPhone 16 Pro",
  simulatorPlatform: "iOS Simulator",
  configuration: "Debug",
  derivedDataPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/.build/DerivedData",
  useLatestOS: true
)
build_sim()
```

Expected: build result `SUCCEEDED`, with no warnings or errors.

- [ ] **Step 4: Build watchOS target**

Use XcodeBuildMCP:

```text
session_set_defaults(
  projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj",
  scheme: "SmartSleepWatch",
  simulatorName: "Apple Watch Series 10 (46mm)",
  simulatorPlatform: "watchOS Simulator",
  configuration: "Debug",
  derivedDataPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/.build/DerivedData",
  useLatestOS: true
)
build_sim()
```

Expected: build result `SUCCEEDED`, with no warnings or errors.

- [ ] **Step 5: Commit baseline**

Run:

```bash
git add .gitignore AGENTS.md Apps Packages README.md docs project.yml
git commit -m "chore: establish smartsleep v02 baseline"
```

Expected: one baseline commit exists. If the repository has not configured user name/email, configure them outside this plan according to the developer machine policy, then rerun the commit.

## Task 2: Add Pure Swift Alarm Repository Contract

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

Expected: compile failure saying `cannot find 'MemoryAlarmRepository' in scope`.

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
            if lhsHour != rhsHour {
                return lhsHour < rhsHour
            }
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

- [ ] **Step 5: Run all core tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRepository.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRepositoryTests.swift
git commit -m "feat: add alarm repository contract"
```

## Task 3: Add Backup Scheduling Policy in Core

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmSchedulerPolicyTests.swift`

- [ ] **Step 1: Write failing scheduling policy tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmSchedulerPolicyTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class AlarmSchedulerPolicyTests: XCTestCase {
    func testSmartAlarmWithoutWatchArmingRequiresPhoneBackup() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let decision = AlarmSchedulerPolicy().decision(for: alarm, arming: nil)

        XCTAssertEqual(decision.smartModeStatus, .needsWatchArming)
        XCTAssertEqual(decision.requiredBackupChannel, .iOSAlarmKit)
        XCTAssertTrue(decision.shouldSyncToWatch)
        XCTAssertTrue(decision.shouldSchedulePhoneBackup)
    }

    func testReadySmartAlarmStillKeepsBackupVisibleInV02() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let arming = WatchArmingStatus(
            alarmId: alarm.id,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSAlarmKit,
            failureReason: nil
        )

        let decision = AlarmSchedulerPolicy().decision(for: alarm, arming: arming)

        XCTAssertEqual(decision.smartModeStatus, .ready)
        XCTAssertTrue(decision.shouldSchedulePhoneBackup)
        XCTAssertEqual(decision.requiredBackupChannel, .iOSAlarmKit)
    }

    func testSmartOffAlarmDoesNotSyncToWatch() {
        let alarm = Alarm.fixture(smartEnabled: false)
        let decision = AlarmSchedulerPolicy().decision(for: alarm, arming: nil)

        XCTAssertEqual(decision.smartModeStatus, .smartOff)
        XCTAssertFalse(decision.shouldSyncToWatch)
        XCTAssertTrue(decision.shouldSchedulePhoneBackup)
    }
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmSchedulerPolicyTests
```

Expected: compile failure saying `cannot find 'AlarmSchedulerPolicy' in scope`.

- [ ] **Step 3: Implement scheduling policy**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift`:

```swift
import Foundation

public struct AlarmSchedulingDecision: Equatable, Sendable {
    public var smartModeStatus: SmartModeStatus
    public var shouldSyncToWatch: Bool
    public var shouldSchedulePhoneBackup: Bool
    public var requiredBackupChannel: AlarmChannel
}

public struct AlarmSchedulerPolicy: Sendable {
    public init() {}

    public func decision(for alarm: Alarm, arming: WatchArmingStatus?) -> AlarmSchedulingDecision {
        let status = SmartModeResolver.status(for: alarm, arming: arming)
        return AlarmSchedulingDecision(
            smartModeStatus: status,
            shouldSyncToWatch: alarm.isEnabled && alarm.smartEnabled,
            shouldSchedulePhoneBackup: alarm.isEnabled,
            requiredBackupChannel: arming?.fallbackChannel ?? alarm.backupChannelPreferred
        )
    }
}
```

- [ ] **Step 4: Run policy tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmSchedulerPolicyTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmSchedulerPolicyTests.swift
git commit -m "feat: add alarm scheduling policy"
```

## Task 4: Add iOS File Repository Adapter

**Files:**
- Create: `Apps/iOS/Sources/AlarmFileRepositoryAdapter.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`

- [ ] **Step 1: Create file-backed repository adapter**

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
            if lhsHour != rhsHour {
                return lhsHour < rhsHour
            }
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
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

- [ ] **Step 2: Refactor iOS state into an app model**

Modify `Apps/iOS/Sources/SmartSleepAlarmApp.swift` by introducing a model near the top of the file:

```swift
@MainActor
final class AlarmDashboardModel: ObservableObject {
    @Published private(set) var alarms: [AlarmCardState]
    @Published var exportedLogText = ""
    private let repository: AlarmRepository

    init(repository: AlarmRepository = MemoryAlarmRepository(alarms: AlarmCardState.seed.map(\.alarm))) {
        self.repository = repository
        self.alarms = AlarmCardState.seed
    }

    func create(_ alarm: AlarmCardState) {
        do {
            try repository.save(alarm.alarm)
            alarms.append(alarm)
            alarms.sort { $0.nextFireAt < $1.nextFireAt }
        } catch {
            exportedLogText = #"{"error":"failed_to_save_alarm"}"#
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { alarms[$0].id }
        do {
            for id in ids {
                try repository.delete(id: id)
            }
            alarms.remove(atOffsets: offsets)
        } catch {
            exportedLogText = #"{"error":"failed_to_delete_alarm"}"#
        }
    }

    func exportPreview() {
        exportedLogText = LogPreviewBuilder.makePreview(for: alarms)
    }
}
```

Then replace local `@State private var alarms` and `exportedLogText` in `AlarmDashboardView` with:

```swift
@StateObject private var model = AlarmDashboardModel()
@State private var isCreatingAlarm = false
```

Update all references:

```swift
ForEach(model.alarms) { alarm in
    AlarmCard(alarm: alarm)
}
.onDelete(perform: model.delete)

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

CreateAlarmView { alarm in
    model.create(alarm)
}
```

- [ ] **Step 3: Build iOS target**

Use XcodeBuildMCP:

```text
session_set_defaults(
  projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj",
  scheme: "SmartSleepAlarm",
  simulatorName: "iPhone 16 Pro",
  simulatorPlatform: "iOS Simulator",
  configuration: "Debug",
  derivedDataPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/.build/DerivedData",
  useLatestOS: true
)
build_sim()
```

Expected: build result `SUCCEEDED`.

- [ ] **Step 4: Commit**

Run:

```bash
git add Apps/iOS/Sources/AlarmFileRepositoryAdapter.swift Apps/iOS/Sources/SmartSleepAlarmApp.swift
git commit -m "feat: persist iphone alarms"
```

## Task 5: Add iOS Backup Notification Scheduler

**Files:**
- Create: `Apps/iOS/Sources/BackupAlarmScheduler.swift`
- Create: `Apps/iOS/Sources/NotificationPermissionService.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`
- Modify: `Apps/iOS/Info.plist` through `project.yml` only if notification usage text or capabilities require generated settings

- [ ] **Step 1: Add permission service**

Create `Apps/iOS/Sources/NotificationPermissionService.swift`:

```swift
import Foundation
import UserNotifications

struct NotificationPermissionService {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }
}
```

- [ ] **Step 2: Add backup scheduler adapter**

Create `Apps/iOS/Sources/BackupAlarmScheduler.swift`:

```swift
import Foundation
import SmartSleepCore
import UserNotifications

struct BackupAlarmScheduler {
    func scheduleBackup(for alarm: Alarm, nextFireAt: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "SmartSleep Alarm" : alarm.label
        content.body = "iPhone fallback alarm"
        content.sound = .defaultCritical

        let components = Calendar.current.dateComponents([.hour, .minute], from: nextFireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: !alarm.repeatDays.isEmpty)
        let request = UNNotificationRequest(
            identifier: "backup-\(alarm.id.uuidString)",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    func cancelBackup(for alarmId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["backup-\(alarmId.uuidString)"])
    }
}
```

If `.defaultCritical` does not compile because the entitlement is unavailable, replace only that line with:

```swift
content.sound = .default
```

Record the downgrade in `docs/spikes/Spike-B-alarm-channel-reliability.md`.

- [ ] **Step 3: Schedule backup when creating an alarm**

Modify `AlarmDashboardModel` in `Apps/iOS/Sources/SmartSleepAlarmApp.swift` to own:

```swift
private let backupScheduler = BackupAlarmScheduler()
```

Change `func create(_ alarm: AlarmCardState)` to:

```swift
func create(_ alarm: AlarmCardState) {
    do {
        try repository.save(alarm.alarm)
        alarms.append(alarm)
        alarms.sort { $0.nextFireAt < $1.nextFireAt }
        Task {
            try? await backupScheduler.scheduleBackup(for: alarm.alarm, nextFireAt: alarm.nextFireAt)
        }
    } catch {
        exportedLogText = #"{"error":"failed_to_save_alarm"}"#
    }
}
```

Change delete to cancel backup:

```swift
func delete(at offsets: IndexSet) {
    let ids = offsets.map { alarms[$0].id }
    do {
        for id in ids {
            try repository.delete(id: id)
            backupScheduler.cancelBackup(for: id)
        }
        alarms.remove(atOffsets: offsets)
    } catch {
        exportedLogText = #"{"error":"failed_to_delete_alarm"}"#
    }
}
```

- [ ] **Step 4: Build iOS target**

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm`.

Expected: build result `SUCCEEDED`. If notification sound entitlement fails, make the documented `.default` downgrade and rebuild.

- [ ] **Step 5: Manual Simulator check**

Use XcodeBuildMCP:

```text
build_run_sim()
snapshot_ui()
```

Expected: app launches and still shows `Fallback`, `Ready`, `Needs Watch`, and `导出本地 JSON 预览`.

- [ ] **Step 6: Commit**

Run:

```bash
git add Apps/iOS/Sources/BackupAlarmScheduler.swift Apps/iOS/Sources/NotificationPermissionService.swift Apps/iOS/Sources/SmartSleepAlarmApp.swift docs/spikes/Spike-B-alarm-channel-reliability.md
git commit -m "feat: schedule iphone backup notifications"
```

## Task 6: Add Real iOS WatchConnectivity Sender/Receiver

**Files:**
- Create: `Apps/iOS/Sources/IOSConnectivityService.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`

- [ ] **Step 1: Create iOS connectivity service**

Create `Apps/iOS/Sources/IOSConnectivityService.swift`:

```swift
import Foundation
import SmartSleepCore
import WatchConnectivity

@MainActor
final class IOSConnectivityService: NSObject, ObservableObject {
    @Published private(set) var lastArmingStatus: WatchArmingStatus?
    @Published private(set) var lastSessionResult: SessionResultPayload?
    @Published private(set) var lastRunSummary: RunLogSummaryPayload?
    @Published private(set) var outboundOutbox: [SmartSleepConnectivityMessage] = []

    private let session: WCSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        self.session?.delegate = self
        self.session?.activate()
    }

    func sendAlarmConfig(_ payload: AlarmConfigPayload) {
        send(.alarmConfig(payload))
    }

    func cancelAlarm(id: UUID) {
        send(.alarmCancelled(alarmId: id))
    }

    private func send(_ message: SmartSleepConnectivityMessage) {
        guard let data = try? encoder.encode(message),
              let session else {
            outboundOutbox.append(message)
            return
        }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.outboundOutbox.append(message)
                }
            }
        } else {
            do {
                try session.updateApplicationContext(["message": data])
            } catch {
                outboundOutbox.append(message)
            }
        }
    }

    private func receive(_ data: Data) {
        guard let message = try? decoder.decode(SmartSleepConnectivityMessage.self, from: data) else {
            return
        }
        switch message {
        case let .armingResult(payload):
            lastArmingStatus = payload.status
        case let .sessionResult(payload):
            lastSessionResult = payload
        case let .runLogSummary(payload):
            lastRunSummary = payload
        case .alarmConfig, .alarmCancelled:
            break
        }
    }
}

extension IOSConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            self.receive(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["message"] as? Data else {
            return
        }
        Task { @MainActor in
            self.receive(data)
        }
    }
}
```

- [ ] **Step 2: Wire connectivity into iOS model**

Modify `AlarmDashboardModel` in `Apps/iOS/Sources/SmartSleepAlarmApp.swift`:

```swift
private let connectivity = IOSConnectivityService()
```

Inside `func create(_ alarm: AlarmCardState)`, after backup scheduling:

```swift
if alarm.alarm.smartEnabled {
    connectivity.sendAlarmConfig(AlarmConfigPayload(alarm: alarm.alarm, nextFireAt: alarm.nextFireAt))
}
```

Inside delete loop:

```swift
connectivity.cancelAlarm(id: id)
```

- [ ] **Step 3: Build iOS target**

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm`.

Expected: build result `SUCCEEDED`.

- [ ] **Step 4: Commit**

Run:

```bash
git add Apps/iOS/Sources/IOSConnectivityService.swift Apps/iOS/Sources/SmartSleepAlarmApp.swift
git commit -m "feat: send iphone alarm configs to watch"
```

## Task 7: Add Watch Connectivity Receiver and Arming Model

**Files:**
- Create: `Apps/Watch/Sources/WatchConnectivityService.swift`
- Create: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `Apps/Watch/Sources/SmartSleepWatchApp.swift`

- [ ] **Step 1: Create Watch connectivity service**

Create `Apps/Watch/Sources/WatchConnectivityService.swift`:

```swift
import Foundation
import SmartSleepCore
import WatchConnectivity

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject {
    @Published private(set) var latestAlarmConfig: AlarmConfigPayload?
    @Published private(set) var outboundOutbox: [SmartSleepConnectivityMessage] = []

    private let session: WCSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        self.session?.delegate = self
        self.session?.activate()
    }

    func sendArmingResult(_ payload: ArmingResultPayload) {
        send(.armingResult(payload))
    }

    func sendSessionResult(_ payload: SessionResultPayload) {
        send(.sessionResult(payload))
    }

    func sendRunLogSummary(_ payload: RunLogSummaryPayload) {
        send(.runLogSummary(payload))
    }

    private func send(_ message: SmartSleepConnectivityMessage) {
        guard let data = try? encoder.encode(message),
              let session else {
            outboundOutbox.append(message)
            return
        }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in
                    self?.outboundOutbox.append(message)
                }
            }
        } else {
            do {
                try session.updateApplicationContext(["message": data])
            } catch {
                outboundOutbox.append(message)
            }
        }
    }

    private func receive(_ data: Data) {
        guard let message = try? decoder.decode(SmartSleepConnectivityMessage.self, from: data) else {
            return
        }
        switch message {
        case let .alarmConfig(payload):
            latestAlarmConfig = payload
        case .alarmCancelled:
            latestAlarmConfig = nil
        case .armingResult, .sessionResult, .runLogSummary:
            break
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in
            self.receive(messageData)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["message"] as? Data else {
            return
        }
        Task { @MainActor in
            self.receive(data)
        }
    }
}
```

- [ ] **Step 2: Create Watch app model**

Create `Apps/Watch/Sources/WatchAppModel.swift`:

```swift
import Foundation
import SmartSleepCore

@MainActor
final class WatchAppModel: ObservableObject {
    @Published var currentState: SmartAlarmState = .needsWatchArming
    @Published var sessionScheduled = false
    @Published var lastConfig: AlarmConfigPayload?

    private let connectivity: WatchConnectivityService

    init(connectivity: WatchConnectivityService = WatchConnectivityService()) {
        self.connectivity = connectivity
    }

    func refreshFromConnectivity() {
        lastConfig = connectivity.latestAlarmConfig
    }

    func armCurrentAlarm() {
        let alarmId = lastConfig?.alarm.id ?? UUID()
        sessionScheduled = true
        currentState = .sessionScheduled
        let status = WatchArmingStatus(
            alarmId: alarmId,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSAlarmKit,
            failureReason: nil
        )
        connectivity.sendArmingResult(ArmingResultPayload(
            alarmId: alarmId,
            armedAt: Date(),
            status: status
        ))
    }

    func simulateRinging() {
        currentState = .ringing
    }

    func snooze() {
        currentState = .snoozed
    }

    func stop() {
        currentState = .completed
    }
}
```

- [ ] **Step 3: Wire Watch UI to model**

Modify `Apps/Watch/Sources/SmartSleepWatchApp.swift`:

```swift
private struct WatchArmingView: View {
    @StateObject private var model = WatchAppModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.lastConfig?.nextFireAt.formatted(date: .omitted, time: .shortened) ?? "07:30")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("下一次闹铃")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    StatusLine(title: "佩戴状态", value: "可用", systemImage: "applewatch")
                    StatusLine(title: "Motion", value: "已启用", systemImage: "sensor.tag.radiowaves.forward")
                    StatusLine(title: "iPhone 兜底", value: "AlarmKit", systemImage: "iphone")
                    StatusLine(title: "Runtime", value: model.sessionScheduled ? "已预约" : "待预约", systemImage: "clock.badge.checkmark")

                    Button {
                        model.armCurrentAlarm()
                    } label: {
                        Label(model.sessionScheduled ? "已武装" : "今晚启用", systemImage: model.sessionScheduled ? "checkmark.seal.fill" : "bolt.badge.clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sessionScheduled)

                    Divider()

                    RingingControls(currentState: $model.currentState)
                }
                .padding(.vertical)
            }
            .navigationTitle("SmartSleep")
            .task {
                model.refreshFromConnectivity()
            }
        }
    }
}
```

- [ ] **Step 4: Build watchOS target**

Use XcodeBuildMCP `build_sim()` for `SmartSleepWatch`.

Expected: build result `SUCCEEDED`.

- [ ] **Step 5: Commit**

Run:

```bash
git add Apps/Watch/Sources/WatchConnectivityService.swift Apps/Watch/Sources/WatchAppModel.swift Apps/Watch/Sources/SmartSleepWatchApp.swift
git commit -m "feat: receive watch alarm configs"
```

## Task 8: Add Watch Runtime Session Scheduler

**Files:**
- Create: `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `docs/spikes/Spike-A-watch-runtime-session.md`

- [ ] **Step 1: Add runtime scheduler**

Create `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`:

```swift
import Foundation
import SmartSleepCore
import WatchKit

@MainActor
final class WatchRuntimeSessionScheduler: NSObject, ObservableObject {
    @Published private(set) var latestLog: RuntimeSessionLog?

    private var session: WKExtendedRuntimeSession?

    func schedule(for payload: AlarmConfigPayload, runId: UUID = UUID()) -> RuntimeSessionLog {
        let targetStart = payload.nextFireAt.addingTimeInterval(-30 * 60)
        let now = Date()
        let newSession = WKExtendedRuntimeSession()
        newSession.delegate = self
        session = newSession

        let log = RuntimeSessionLog(
            runId: runId,
            sessionType: "smartAlarmPreMonitoring",
            scheduledAt: now,
            targetStartAt: targetStart,
            actualStartAt: nil,
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: nil,
            didStartBeforeAlarm: false,
            didReachRingTime: false,
            errorCode: nil,
            errorMessage: nil
        )
        latestLog = log

        if targetStart <= now {
            newSession.start()
        } else {
            newSession.start(at: targetStart)
        }

        return log
    }

    func invalidate() {
        session?.invalidate()
        session = nil
    }
}

extension WatchRuntimeSessionScheduler: WKExtendedRuntimeSessionDelegate {
    nonisolated func extendedRuntimeSessionDidStart(_ extendedRuntimeSession: WKExtendedRuntimeSession) {
        Task { @MainActor in
            guard var log = latestLog else {
                return
            }
            let now = Date()
            log.actualStartAt = now
            log.startLatencySec = now.timeIntervalSince(log.targetStartAt)
            log.didStartBeforeAlarm = true
            latestLog = log
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ extendedRuntimeSession: WKExtendedRuntimeSession) {}

    nonisolated func extendedRuntimeSession(
        _ extendedRuntimeSession: WKExtendedRuntimeSession,
        didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
        error: Error?
    ) {
        Task { @MainActor in
            guard var log = latestLog else {
                return
            }
            log.invalidatedAt = Date()
            log.invalidationReason = String(describing: reason)
            log.errorMessage = error?.localizedDescription
            latestLog = log
        }
    }
}
```

- [ ] **Step 2: Wire runtime scheduler into Watch app model**

Modify `Apps/Watch/Sources/WatchAppModel.swift`:

```swift
private let runtimeScheduler = WatchRuntimeSessionScheduler()
```

Change `armCurrentAlarm()`:

```swift
func armCurrentAlarm() {
    let alarmId = lastConfig?.alarm.id ?? UUID()
    if let config = lastConfig {
        let log = runtimeScheduler.schedule(for: config)
        sessionScheduled = log.errorCode == nil
    } else {
        sessionScheduled = true
    }
    currentState = sessionScheduled ? .sessionScheduled : .fallbackPhoneAlarm
    let status = WatchArmingStatus(
        alarmId: alarmId,
        isArmed: true,
        sessionScheduled: sessionScheduled,
        fallbackChannel: .iOSAlarmKit,
        failureReason: sessionScheduled ? nil : "runtime_session_not_scheduled"
    )
    connectivity.sendArmingResult(ArmingResultPayload(
        alarmId: alarmId,
        armedAt: Date(),
        status: status
    ))
}
```

- [ ] **Step 3: Build watchOS target**

Use XcodeBuildMCP `build_sim()` for `SmartSleepWatch`.

Expected: build result `SUCCEEDED`. If `start(at:)` availability differs on the installed SDK, use the SDK-supported method and record the exact method in `docs/spikes/Spike-A-watch-runtime-session.md`.

- [ ] **Step 4: Update Spike A with implementation note**

Modify `docs/spikes/Spike-A-watch-runtime-session.md`:

```markdown
## Implementation Hook

The first runtime-session adapter lives at `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`.
Simulator build verifies compile-time API usage only. The matrix below must be filled from paired real iPhone + Apple Watch tests because Simulator cannot prove background scheduling, lock-screen behavior, force-quit behavior, low battery behavior, or night-time reliability.
```

- [ ] **Step 5: Commit**

Run:

```bash
git add Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift Apps/Watch/Sources/WatchAppModel.swift docs/spikes/Spike-A-watch-runtime-session.md
git commit -m "feat: schedule watch runtime sessions"
```

## Task 9: Add Run Coordinator and JSONL Export Flow

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRunCoordinator.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRunCoordinatorTests.swift`
- Create: `Apps/iOS/Sources/LogExportService.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`

- [ ] **Step 1: Write failing coordinator tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRunCoordinatorTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class AlarmRunCoordinatorTests: XCTestCase {
    func testCoordinatorLogsStateTransitions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try JSONLAlarmEventStore(directory: directory)
        var coordinator = AlarmRunCoordinator(runId: UUID(), eventStore: store)

        try coordinator.apply(.phoneCreatedAlarm, reason: "created_on_phone")
        try coordinator.apply(.watchArmed, reason: "watch_armed")

        let exported = try store.export(runId: coordinator.runId)
        XCTAssertEqual(exported.count, 2)
        XCTAssertTrue(exported[0].contains("created_on_phone"))
        XCTAssertTrue(exported[1].contains("watch_armed"))
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmRunCoordinatorTests
```

Expected: compile failure saying `cannot find 'AlarmRunCoordinator' in scope`.

- [ ] **Step 3: Implement coordinator**

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
}
```

- [ ] **Step 4: Run coordinator tests and all tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmRunCoordinatorTests
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: coordinator tests pass, then all tests pass.

- [ ] **Step 5: Add iOS export service**

Create `Apps/iOS/Sources/LogExportService.swift`:

```swift
import Foundation
import SmartSleepCore

struct LogExportService {
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

- [ ] **Step 6: Build iOS target**

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm`.

Expected: build result `SUCCEEDED`.

- [ ] **Step 7: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmRunCoordinator.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmRunCoordinatorTests.swift Apps/iOS/Sources/LogExportService.swift
git commit -m "feat: coordinate alarm run logs"
```

## Task 10: Add Feature Flags for Experimental Behavior

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/FeatureFlags.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/FeatureFlagsTests.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `docs/qa/dogfood-runbook.md`

- [ ] **Step 1: Write failing feature flag tests**

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
        XCTAssertEqual(flags.maxReAlarmCount, 2)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter FeatureFlagsTests
```

Expected: compile failure saying `cannot find 'FeatureFlags' in scope`.

- [ ] **Step 3: Implement flags**

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

- [ ] **Step 4: Gate Watch snooze path by flags**

Modify `Apps/Watch/Sources/WatchAppModel.swift`:

```swift
private let featureFlags: FeatureFlags

init(
    connectivity: WatchConnectivityService = WatchConnectivityService(),
    featureFlags: FeatureFlags = .v02Default
) {
    self.connectivity = connectivity
    self.featureFlags = featureFlags
}

func snooze() {
    guard featureFlags.gestureSnoozeEnabled else {
        return
    }
    currentState = .snoozed
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

- [ ] **Step 6: Run tests and builds**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm` and `SmartSleepWatch`.

Expected: all tests pass and both builds succeed.

- [ ] **Step 7: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/FeatureFlags.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/FeatureFlagsTests.swift Apps/Watch/Sources/WatchAppModel.swift docs/qa/dogfood-runbook.md
git commit -m "feat: add v02 feature flags"
```

## Task 11: Update Device Spike Documentation After First Integration Build

**Files:**
- Modify: `docs/spikes/Spike-A-watch-runtime-session.md`
- Modify: `docs/spikes/Spike-B-alarm-channel-reliability.md`
- Modify: `docs/qa/device-test-matrix.md`

- [ ] **Step 1: Add build evidence section to Spike A**

Append to `docs/spikes/Spike-A-watch-runtime-session.md`:

```markdown
## Build Evidence

- watchOS Simulator compile check: run `SmartSleepWatch` scheme with XcodeBuildMCP `build_sim()`.
- This check proves API compilation only.
- Real-device rows remain required for scheduling reliability, lock-screen behavior, force-quit behavior, low battery behavior, disconnected phone behavior, and overnight behavior.
```

- [ ] **Step 2: Add build evidence section to Spike B**

Append to `docs/spikes/Spike-B-alarm-channel-reliability.md`:

```markdown
## Build Evidence

- iOS Simulator compile check: run `SmartSleepAlarm` scheme with XcodeBuildMCP `build_sim()`.
- Simulator notification behavior does not prove alarm reliability.
- Real-device rows remain required for Silent Mode, Sleep Focus, Do Not Disturb, locked screen, app backgrounded, app terminated, low battery, and disconnected Watch.
```

- [ ] **Step 3: Update device matrix with integration rows**

Append to `docs/qa/device-test-matrix.md`:

```markdown
| Connectivity | iPhone sends alarm config | Watch receives config and can arm | Simulator compile only | Pending |
| Connectivity | Watch sends arming result | iPhone status updates to Ready or Fallback | Simulator compile only | Pending |
| Runtime | Watch schedules runtime session | Runtime log records scheduled target start | Simulator compile only | Pending |
| Fallback | iPhone backup notification scheduled | `AlarmChannelLog` records backup channel | Simulator partial | Pending |
| Export | AlarmRun JSONL export | Export contains state and channel events | Covered by core test | Pending |
```

- [ ] **Step 4: Commit**

Run:

```bash
git add docs/spikes/Spike-A-watch-runtime-session.md docs/spikes/Spike-B-alarm-channel-reliability.md docs/qa/device-test-matrix.md
git commit -m "docs: update integration spike matrices"
```

## Task 12: Final Verification Gate for This Integration Phase

**Files:**
- Existing: all modified source and docs

- [ ] **Step 1: Regenerate project**

Run:

```bash
xcodegen generate
```

Expected: project generation succeeds.

- [ ] **Step 2: Run all core tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all XCTest suites pass with 0 failures.

- [ ] **Step 3: Build and launch iOS app**

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

- Build result `SUCCEEDED`.
- Snapshot contains `SmartSleep`.
- Snapshot contains at least one of `Ready`, `Needs Watch`, or `Fallback`.
- App is stopped after verification.

- [ ] **Step 4: Build watchOS app**

Use XcodeBuildMCP:

```text
session_set_defaults(
  projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj",
  scheme: "SmartSleepWatch",
  simulatorName: "Apple Watch Series 10 (46mm)",
  simulatorPlatform: "watchOS Simulator",
  configuration: "Debug",
  derivedDataPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/.build/DerivedData",
  useLatestOS: true
)
build_sim()
```

Expected: build result `SUCCEEDED`.

- [ ] **Step 5: Inspect git status**

Run:

```bash
git status --short
```

Expected: only intentional source/doc changes are present, or the branch is clean after commits. No `.build/`, `DerivedData/`, `.xcuserdata/`, or simulator logs appear.

## Scope Boundaries

Do not implement these in this integration phase:

- Sleep reports, sleep stage detection, medical claims, audio recording, cloud sync, subscriptions, Android, Wear OS, or ML personalization.
- Auto-silence default enablement.
- Re-sleep detection default enablement.
- Claims that Simulator validates real alarm reliability.
- Claims that Local Notification or third-party Watch haptic/audio is equivalent to Apple system alarm behavior.

## Self-Review

Spec coverage:

- FR-1 iOS alarm CRUD: covered by Tasks 2, 3, 4, and 5.
- FR-2 Watch arming and readiness: covered by Tasks 6, 7, and 8.
- FR-4 ringing/fallback channel foundation: covered by Tasks 5, 8, 9, and 11.
- FR-7 gesture snooze guard: covered by existing core tests and Task 10 feature flags.
- FR-8 degradation/exception visibility: covered by Tasks 3, 5, 8, 10, and 11.
- FR-9 local logs/export: covered by Task 9.
- Spike A/B documentation: covered by Tasks 8 and 11.

Known remaining work after this plan:

- CoreMotion sampling adapter.
- HealthKit freshness adapter.
- Watch haptic/audio ringer with real device behavior logging.
- AlarmKit adapter after confirming target SDK availability and entitlement behavior.
- Real-device Spike A-F matrix execution.

Red-flag scan:

- This plan intentionally contains no deferred work markers or open-ended implementation steps.
- Rows marked `Pending` or `Not tested` belong to device-test matrices and represent required future test results, not missing implementation instructions.

Type consistency:

- `AlarmConfigPayload`, `ArmingResultPayload`, `SessionResultPayload`, `RunLogSummaryPayload`, `WatchArmingStatus`, `AlarmChannel`, `SmartAlarmState`, `SmartAlarmEvent`, and `FeatureFlags` are consistently named with existing core types or types introduced by this plan.

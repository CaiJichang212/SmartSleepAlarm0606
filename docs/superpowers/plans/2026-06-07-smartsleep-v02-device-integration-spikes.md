# SmartSleep v0.2 Device Integration Spikes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add protocol-backed Apple device adapters and real-device evidence gates for iPhone-Watch pairing, `WCSession`, notification fallback, Watch runtime sessions, Watch ringing controls, and QA matrices.

**Architecture:** This plan starts only after `v02-app-state-and-logging` is complete. App models depend on small protocols and fake implementations first, then real Apple adapters. Simulator builds prove compilation and basic UI state only; paired real devices are required for final integration evidence.

**Tech Stack:** Swift 6.1, SwiftUI, XcodeGen, XCTest where pure Swift is available, WatchConnectivity, UserNotifications, WatchKit `WKExtendedRuntimeSession`, XcodeBuildMCP, paired iPhone + Apple Watch manual QA.

---

## Preconditions

- `docs/superpowers/plans/2026-06-07-smartsleep-v02-app-state-and-logging.md` has been completed.
- Core tests pass.
- `SmartSleepAlarm` builds and launches in iOS Simulator.
- App state and JSONL logs are already wired through `AlarmDashboardModel`.

## File Structure

```text
project.yml

Apps/iOS/Sources/
  AppModel.swift
  BackupAlarmScheduler.swift
  IOSConnectivityService.swift
  NotificationPermissionService.swift

Apps/Watch/Sources/
  SmartSleepWatchApp.swift
  WatchAppModel.swift
  WatchAlarmRinger.swift
  WatchConnectivityService.swift
  WatchRuntimeSessionScheduler.swift

docs/spikes/
  Spike-A-watch-runtime-session.md
  Spike-B-alarm-channel-reliability.md

docs/qa/
  device-test-matrix.md
  dogfood-runbook.md
```

## Task 1: Verify App State Baseline

**Files:**
- Existing: all files from the app-state plan

- [ ] **Step 1: Run core tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all XCTest suites pass with 0 failures.

- [ ] **Step 2: Build iOS and watchOS baselines**

Run:

```bash
xcodegen generate
```

Use XcodeBuildMCP. Before the first build call in the session, run `session_show_defaults()`.

Build iOS:

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

Build watchOS:

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

Expected: project generation succeeds and both builds return `SUCCEEDED`.

## Task 2: Pair and Embed Watch App Before WCSession

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Modify target relationship**

Modify `project.yml` so the iOS app embeds the Watch app and the Watch app declares its companion:

```yaml
targets:
  SmartSleepAlarm:
    type: application
    platform: iOS
    sources:
      - path: Apps/iOS/Sources
    dependencies:
      - package: SmartSleepCore
      - target: SmartSleepWatch
        embed: true
    info:
      path: Apps/iOS/Info.plist
      properties:
        CFBundleDisplayName: SmartSleep
        CFBundleShortVersionString: "0.2"
        CFBundleVersion: "1"
        UILaunchScreen: {}
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.smartsleep.alarm
        MARKETING_VERSION: "0.2"
        CURRENT_PROJECT_VERSION: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
  SmartSleepWatch:
    type: application
    platform: watchOS
    sources:
      - path: Apps/Watch/Sources
    dependencies:
      - package: SmartSleepCore
    info:
      path: Apps/Watch/Info.plist
      properties:
        CFBundleDisplayName: SmartSleep
        CFBundleShortVersionString: "0.2"
        CFBundleVersion: "1"
        WKApplication: true
        WKCompanionAppBundleIdentifier: com.smartsleep.alarm
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.smartsleep.alarm.watch
        MARKETING_VERSION: "0.2"
        CURRENT_PROJECT_VERSION: "1"
```

- [ ] **Step 2: Regenerate project**

Run:

```bash
xcodegen generate
```

Expected: generation succeeds. If XcodeGen rejects `embed: true` for a watchOS app, this task is blocked. Correct `project.yml` using XcodeGen's supported Watch companion syntax, regenerate, and rerun this task before any `WCSession` work.

- [ ] **Step 3: Build both targets**

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm` and `SmartSleepWatch`.

Expected: both builds return `SUCCEEDED`.

- [ ] **Step 4: Commit**

Run:

```bash
git add project.yml
git commit -m "chore: pair iphone and watch targets"
```

## Task 3: Add Protocol-Backed Notification Fallback

**Files:**
- Create: `Apps/iOS/Sources/NotificationPermissionService.swift`
- Create: `Apps/iOS/Sources/BackupAlarmScheduler.swift`
- Modify: `Apps/iOS/Sources/AppModel.swift`
- Modify: `docs/spikes/Spike-B-alarm-channel-reliability.md`

- [ ] **Step 1: Add notification authorization protocol and real adapter**

Create `Apps/iOS/Sources/NotificationPermissionService.swift`:

```swift
import Foundation
import SmartSleepCore
import UserNotifications

protocol NotificationAuthorizing {
    func requestAuthorization() async throws -> AuthorizationState
    func authorizationState() async -> AuthorizationState
}

struct NotificationPermissionService: NotificationAuthorizing {
    func requestAuthorization() async throws -> AuthorizationState {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return granted ? .authorized : .denied
    }

    func authorizationState() async -> AuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }
}

struct FakeNotificationAuthorizer: NotificationAuthorizing {
    var state: AuthorizationState

    func requestAuthorization() async throws -> AuthorizationState {
        state
    }

    func authorizationState() async -> AuthorizationState {
        state
    }
}
```

- [ ] **Step 2: Add backup scheduler protocol, fake, and real adapter**

Create `Apps/iOS/Sources/BackupAlarmScheduler.swift`:

```swift
import Foundation
import SmartSleepCore
import UserNotifications

protocol BackupAlarmScheduling {
    func scheduleBackup(for alarm: Alarm, nextFireAt: Date, runId: UUID, authorizationState: AuthorizationState) async throws -> AlarmChannelLog
    func cancelBackup(for alarmId: UUID)
}

struct RecordingBackupAlarmScheduler: BackupAlarmScheduling {
    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState
    ) async throws -> AlarmChannelLog {
        AlarmChannelLog(
            runId: runId,
            channel: .iOSLocalNotification,
            scheduledAt: Date(),
            firedAt: nil,
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: authorizationState,
            failureReason: nil,
            userVisibleState: "recorded_without_system_schedule"
        )
    }

    func cancelBackup(for alarmId: UUID) {}
}

struct BackupAlarmScheduler: BackupAlarmScheduling {
    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState
    ) async throws -> AlarmChannelLog {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "SmartSleep Alarm" : alarm.label
        content.body = "iPhone fallback alarm"
        content.sound = .default

        let components = Calendar.current.dateComponents([.hour, .minute], from: nextFireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: !alarm.repeatDays.isEmpty)
        let request = UNNotificationRequest(
            identifier: "backup-\(alarm.id.uuidString)",
            content: content,
            trigger: trigger
        )
        try await UNUserNotificationCenter.current().add(request)

        return AlarmChannelLog(
            runId: runId,
            channel: .iOSLocalNotification,
            scheduledAt: Date(),
            firedAt: nil,
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: authorizationState,
            failureReason: nil,
            userVisibleState: "scheduled"
        )
    }

    func cancelBackup(for alarmId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["backup-\(alarmId.uuidString)"])
    }
}
```

- [ ] **Step 3: Inject protocols into app model**

Modify `Apps/iOS/Sources/AppModel.swift`:

```swift
@Published var notificationAuthorizationState: AuthorizationState = .unknown

private let notificationAuthorizer: NotificationAuthorizing
private let backupScheduler: BackupAlarmScheduling
private let schedulerPolicy = AlarmSchedulerPolicy()

init(
    repository: AlarmRepository,
    notificationAuthorizer: NotificationAuthorizing = NotificationPermissionService(),
    backupScheduler: BackupAlarmScheduling = BackupAlarmScheduler()
) {
    self.repository = repository
    self.notificationAuthorizer = notificationAuthorizer
    self.backupScheduler = backupScheduler
    reload()
    Task { await refreshNotificationAuthorization() }
}

func refreshNotificationAuthorization() async {
    notificationAuthorizationState = await notificationAuthorizer.authorizationState()
}

func requestNotificationAuthorization() async {
    do {
        notificationAuthorizationState = try await notificationAuthorizer.requestAuthorization()
    } catch {
        notificationAuthorizationState = .denied
        userVisibleWarning = "Notification permission request failed."
    }
}

private func scheduleFallbackIfNeeded(for item: AlarmCardState, runId: UUID = UUID()) {
    let decision = schedulerPolicy.decision(for: item.alarm, arming: item.armingStatus)
    guard decision.shouldSchedulePhoneBackup else { return }
    Task {
        do {
            let log = try await backupScheduler.scheduleBackup(
                for: item.alarm,
                nextFireAt: item.nextFireAt,
                runId: runId,
                authorizationState: notificationAuthorizationState
            )
            let data = try JSONEncoder().encode(log)
            exportedLogText = String(data: data, encoding: .utf8) ?? ""
        } catch {
            userVisibleWarning = "Failed to schedule fallback notification."
        }
    }
}
```

Call `scheduleFallbackIfNeeded(for: alarm)` after successful alarm creation. In delete, call `backupScheduler.cancelBackup(for: id)`.

- [ ] **Step 4: Update Spike B critical-alert note**

Append to `docs/spikes/Spike-B-alarm-channel-reliability.md`:

```markdown
## Notification Fallback Implementation

v0.2 uses `UNNotificationSound.default` for the iPhone fallback notification. Critical-alert behavior is not a default v0.2 path because it depends on entitlement approval, explicit authorization, Apple review, and product policy.

`Apps/iOS/Sources/BackupAlarmScheduler.swift` records an `AlarmChannelLog` every time the fallback notification is scheduled. Simulator builds prove compile-time API usage and local log visibility only. Real-device rows remain required for Silent Mode, Sleep Focus, locked screen, app terminated, low battery, and disconnected Watch.
```

- [ ] **Step 5: Verify tests, build, and log visibility**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Use XcodeBuildMCP:

```text
build_run_sim()
snapshot_ui()
stop_app_sim()
```

Expected:

- Core tests pass.
- iOS build succeeds.
- Creating an alarm produces visible JSON containing `iOSLocalNotification` in `exportedLogText`.
- The code contains `content.sound = .default`.

- [ ] **Step 6: Commit**

Run:

```bash
git add Apps/iOS/Sources/NotificationPermissionService.swift Apps/iOS/Sources/BackupAlarmScheduler.swift Apps/iOS/Sources/AppModel.swift docs/spikes/Spike-B-alarm-channel-reliability.md
git commit -m "feat: add notification fallback adapter"
```

## Task 4: Add Protocol-Backed iOS WatchConnectivity

**Files:**
- Create: `Apps/iOS/Sources/IOSConnectivityService.swift`
- Modify: `Apps/iOS/Sources/AppModel.swift`

- [ ] **Step 1: Create iOS connectivity protocol, fake, and adapter**

Create `Apps/iOS/Sources/IOSConnectivityService.swift`:

```swift
import Foundation
import SmartSleepCore
import WatchConnectivity

@MainActor
protocol PhoneConnectivityClient: AnyObject {
    var lastArmingStatus: WatchArmingStatus? { get }
    var outboundOutbox: [SmartSleepConnectivityMessage] { get }
    func sendAlarmConfig(_ payload: AlarmConfigPayload)
    func cancelAlarm(id: UUID)
}

@MainActor
final class FakePhoneConnectivityClient: PhoneConnectivityClient {
    private(set) var lastArmingStatus: WatchArmingStatus?
    private(set) var outboundOutbox: [SmartSleepConnectivityMessage] = []

    func sendAlarmConfig(_ payload: AlarmConfigPayload) {
        outboundOutbox.append(.alarmConfig(payload))
    }

    func cancelAlarm(id: UUID) {
        outboundOutbox.append(.alarmCancelled(alarmId: id))
    }
}

@MainActor
final class IOSConnectivityService: NSObject, ObservableObject, PhoneConnectivityClient {
    @Published private(set) var lastArmingStatus: WatchArmingStatus?
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
        guard let data = try? encoder.encode(message), let session else {
            outboundOutbox.append(message)
            return
        }
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.outboundOutbox.append(message) }
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
        guard let message = try? decoder.decode(SmartSleepConnectivityMessage.self, from: data) else { return }
        if case let .armingResult(payload) = message {
            lastArmingStatus = payload.status
        }
    }
}

extension IOSConnectivityService: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.receive(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["message"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
}
```

- [ ] **Step 2: Inject iOS connectivity into app model**

Modify `Apps/iOS/Sources/AppModel.swift`:

```swift
private let connectivity: PhoneConnectivityClient

init(
    repository: AlarmRepository,
    notificationAuthorizer: NotificationAuthorizing = NotificationPermissionService(),
    backupScheduler: BackupAlarmScheduling = BackupAlarmScheduler(),
    connectivity: PhoneConnectivityClient = IOSConnectivityService()
) {
    self.repository = repository
    self.notificationAuthorizer = notificationAuthorizer
    self.backupScheduler = backupScheduler
    self.connectivity = connectivity
    reload()
    Task { await refreshNotificationAuthorization() }
}
```

Inside successful alarm creation, after fallback scheduling:

```swift
if alarm.alarm.smartEnabled {
    connectivity.sendAlarmConfig(AlarmConfigPayload(alarm: alarm.alarm, nextFireAt: alarm.nextFireAt))
}
```

Inside delete:

```swift
connectivity.cancelAlarm(id: id)
```

- [ ] **Step 3: Verify tests, build, and visible local effect**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm`.

Expected:

- Core tests pass.
- iOS build succeeds.
- App model can be constructed with `FakePhoneConnectivityClient` for deterministic local verification.
- Real paired-device delivery is not claimed until Task 8.

- [ ] **Step 4: Commit**

Run:

```bash
git add Apps/iOS/Sources/IOSConnectivityService.swift Apps/iOS/Sources/AppModel.swift
git commit -m "feat: send iphone alarm configs to watch"
```

## Task 5: Add Protocol-Backed Watch Connectivity and Reactive UI

**Files:**
- Create: `Apps/Watch/Sources/WatchConnectivityService.swift`
- Create: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `Apps/Watch/Sources/SmartSleepWatchApp.swift`

- [ ] **Step 1: Create Watch connectivity protocol, fake, and adapter**

Create `Apps/Watch/Sources/WatchConnectivityService.swift`:

```swift
import Foundation
import SmartSleepCore
import WatchConnectivity

@MainActor
protocol WatchConnectivityClient: AnyObject {
    var latestAlarmConfig: AlarmConfigPayload? { get }
    var onConfigChanged: ((AlarmConfigPayload?) -> Void)? { get set }
    func sendArmingResult(_ payload: ArmingResultPayload)
    func sendSessionResult(_ payload: SessionResultPayload)
    func sendRunLogSummary(_ payload: RunLogSummaryPayload)
}

@MainActor
final class FakeWatchConnectivityClient: WatchConnectivityClient {
    var latestAlarmConfig: AlarmConfigPayload? {
        didSet { onConfigChanged?(latestAlarmConfig) }
    }
    var onConfigChanged: ((AlarmConfigPayload?) -> Void)?
    private(set) var outboundMessages: [SmartSleepConnectivityMessage] = []

    init(latestAlarmConfig: AlarmConfigPayload? = nil) {
        self.latestAlarmConfig = latestAlarmConfig
    }

    func sendArmingResult(_ payload: ArmingResultPayload) {
        outboundMessages.append(.armingResult(payload))
    }

    func sendSessionResult(_ payload: SessionResultPayload) {
        outboundMessages.append(.sessionResult(payload))
    }

    func sendRunLogSummary(_ payload: RunLogSummaryPayload) {
        outboundMessages.append(.runLogSummary(payload))
    }
}

@MainActor
final class WatchConnectivityService: NSObject, ObservableObject, WatchConnectivityClient {
    @Published private(set) var latestAlarmConfig: AlarmConfigPayload? {
        didSet { onConfigChanged?(latestAlarmConfig) }
    }
    @Published private(set) var outboundOutbox: [SmartSleepConnectivityMessage] = []

    var onConfigChanged: ((AlarmConfigPayload?) -> Void)?

    private let session: WCSession?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    override init() {
        self.session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        self.session?.delegate = self
        self.session?.activate()
    }

    func sendArmingResult(_ payload: ArmingResultPayload) { send(.armingResult(payload)) }
    func sendSessionResult(_ payload: SessionResultPayload) { send(.sessionResult(payload)) }
    func sendRunLogSummary(_ payload: RunLogSummaryPayload) { send(.runLogSummary(payload)) }

    private func send(_ message: SmartSleepConnectivityMessage) {
        guard let data = try? encoder.encode(message), let session else {
            outboundOutbox.append(message)
            return
        }
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.outboundOutbox.append(message) }
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
        guard let message = try? decoder.decode(SmartSleepConnectivityMessage.self, from: data) else { return }
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
        Task { @MainActor in self.receive(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["message"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
}
```

- [ ] **Step 2: Create Watch app model that fails closed without config**

Create `Apps/Watch/Sources/WatchAppModel.swift`:

```swift
import Foundation
import SmartSleepCore
import SwiftUI

@MainActor
final class WatchAppModel: ObservableObject {
    @Published var currentState: SmartAlarmState = .needsWatchArming
    @Published var sessionScheduled = false
    @Published var lastConfig: AlarmConfigPayload?
    @Published var failureReason: String?

    private let connectivity: WatchConnectivityClient

    init(connectivity: WatchConnectivityClient = WatchConnectivityService()) {
        self.connectivity = connectivity
        self.lastConfig = connectivity.latestAlarmConfig
        self.connectivity.onConfigChanged = { [weak self] config in
            self?.lastConfig = config
            self?.failureReason = config == nil ? "missing_alarm_config" : nil
        }
    }

    func armCurrentAlarm() {
        guard let config = lastConfig else {
            sessionScheduled = false
            currentState = .fallbackPhoneAlarm
            failureReason = "missing_alarm_config"
            let alarmId = UUID()
            let status = WatchArmingStatus(
                alarmId: alarmId,
                isArmed: false,
                sessionScheduled: false,
                fallbackChannel: .iOSLocalNotification,
                failureReason: "missing_alarm_config"
            )
            connectivity.sendArmingResult(ArmingResultPayload(alarmId: alarmId, armedAt: Date(), status: status))
            return
        }

        sessionScheduled = true
        currentState = .sessionScheduled
        failureReason = nil
        let status = WatchArmingStatus(
            alarmId: config.alarm.id,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSLocalNotification,
            failureReason: nil
        )
        connectivity.sendArmingResult(ArmingResultPayload(alarmId: config.alarm.id, armedAt: Date(), status: status))
    }

    func simulateRinging() { currentState = .ringing }
    func snooze() { currentState = .snoozed }
    func stop() { currentState = .completed }
}
```

- [ ] **Step 3: Wire Watch UI to model**

Replace `WatchArmingView` in `Apps/Watch/Sources/SmartSleepWatchApp.swift` with:

```swift
private struct WatchArmingView: View {
    @StateObject private var model = WatchAppModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.lastConfig?.nextFireAt.formatted(date: .omitted, time: .shortened) ?? "--:--")
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("下一次闹铃")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    StatusLine(title: "配置", value: model.lastConfig == nil ? "未收到" : "已收到", systemImage: "antenna.radiowaves.left.and.right")
                    StatusLine(title: "iPhone 兜底", value: "Local Notification", systemImage: "iphone")
                    StatusLine(title: "Runtime", value: model.sessionScheduled ? "已预约" : "待预约", systemImage: "clock.badge.checkmark")

                    if let failureReason = model.failureReason {
                        Text(failureReason)
                            .font(.caption.monospaced())
                            .foregroundStyle(.orange)
                    }

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
        }
    }
}
```

- [ ] **Step 4: Verify build and fail-closed UI**

Use XcodeBuildMCP `build_sim()` for `SmartSleepWatch`.

Expected:

- watchOS build succeeds.
- Watch UI can show `--:--` and `未收到` when no config exists.
- Pressing arm with no config records `missing_alarm_config` instead of Ready.

- [ ] **Step 5: Commit**

Run:

```bash
git add Apps/Watch/Sources/WatchConnectivityService.swift Apps/Watch/Sources/WatchAppModel.swift Apps/Watch/Sources/SmartSleepWatchApp.swift
git commit -m "feat: receive watch alarm configs reactively"
```

## Task 6: Add Watch Runtime Session and Ringer Protocols

**Files:**
- Create: `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`
- Create: `Apps/Watch/Sources/WatchAlarmRinger.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `docs/spikes/Spike-A-watch-runtime-session.md`
- Modify: `docs/spikes/Spike-B-alarm-channel-reliability.md`

- [ ] **Step 1: Add runtime protocol, fake, and real adapter**

Create `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`:

```swift
import Foundation
import SmartSleepCore
import WatchKit

@MainActor
protocol RuntimeSessionScheduling {
    func schedule(for payload: AlarmConfigPayload, runId: UUID) -> RuntimeSessionLog
    func invalidate()
}

@MainActor
struct FakeRuntimeSessionScheduler: RuntimeSessionScheduling {
    var shouldSucceed: Bool

    func schedule(for payload: AlarmConfigPayload, runId: UUID) -> RuntimeSessionLog {
        RuntimeSessionLog(
            runId: runId,
            sessionType: "fakeSmartAlarmPreMonitoring",
            scheduledAt: Date(),
            targetStartAt: payload.nextFireAt.addingTimeInterval(-30 * 60),
            actualStartAt: nil,
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: nil,
            didStartBeforeAlarm: false,
            didReachRingTime: false,
            errorCode: shouldSucceed ? nil : "fake_runtime_schedule_failed",
            errorMessage: shouldSucceed ? nil : "Fake runtime scheduler was configured to fail."
        )
    }

    func invalidate() {}
}

@MainActor
final class WatchRuntimeSessionScheduler: NSObject, ObservableObject, RuntimeSessionScheduling {
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
            guard var log = latestLog else { return }
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
            guard var log = latestLog else { return }
            log.invalidatedAt = Date()
            log.invalidationReason = String(describing: reason)
            log.errorMessage = error?.localizedDescription
            latestLog = log
        }
    }
}
```

- [ ] **Step 2: Add ringer protocol, fake, and real adapter**

Create `Apps/Watch/Sources/WatchAlarmRinger.swift`:

```swift
import Foundation
import WatchKit

@MainActor
protocol WatchAlarmRinging {
    func startRinging()
    func snooze()
    func stop()
}

@MainActor
struct FakeWatchAlarmRinger: WatchAlarmRinging {
    func startRinging() {}
    func snooze() {}
    func stop() {}
}

@MainActor
struct WatchAlarmRinger: WatchAlarmRinging {
    func startRinging() {
        WKInterfaceDevice.current().play(.notification)
    }

    func snooze() {
        WKInterfaceDevice.current().play(.directionDown)
    }

    func stop() {
        WKInterfaceDevice.current().play(.success)
    }
}
```

- [ ] **Step 3: Inject runtime and ringer into Watch model**

Modify `Apps/Watch/Sources/WatchAppModel.swift`:

```swift
private let runtimeScheduler: RuntimeSessionScheduling
private let ringer: WatchAlarmRinging

init(
    connectivity: WatchConnectivityClient = WatchConnectivityService(),
    runtimeScheduler: RuntimeSessionScheduling = WatchRuntimeSessionScheduler(),
    ringer: WatchAlarmRinging = WatchAlarmRinger()
) {
    self.connectivity = connectivity
    self.runtimeScheduler = runtimeScheduler
    self.ringer = ringer
    self.lastConfig = connectivity.latestAlarmConfig
    self.connectivity.onConfigChanged = { [weak self] config in
        self?.lastConfig = config
        self?.failureReason = config == nil ? "missing_alarm_config" : nil
    }
}

func armCurrentAlarm() {
    guard let config = lastConfig else {
        sessionScheduled = false
        currentState = .fallbackPhoneAlarm
        failureReason = "missing_alarm_config"
        let alarmId = UUID()
        let status = WatchArmingStatus(
            alarmId: alarmId,
            isArmed: false,
            sessionScheduled: false,
            fallbackChannel: .iOSLocalNotification,
            failureReason: "missing_alarm_config"
        )
        connectivity.sendArmingResult(ArmingResultPayload(alarmId: alarmId, armedAt: Date(), status: status))
        return
    }

    let runId = UUID()
    let runtimeLog = runtimeScheduler.schedule(for: config, runId: runId)
    sessionScheduled = runtimeLog.errorCode == nil
    currentState = sessionScheduled ? .sessionScheduled : .fallbackPhoneAlarm
    failureReason = sessionScheduled ? nil : "runtime_session_not_scheduled"
    let status = WatchArmingStatus(
        alarmId: config.alarm.id,
        isArmed: sessionScheduled,
        sessionScheduled: sessionScheduled,
        fallbackChannel: .iOSLocalNotification,
        failureReason: failureReason
    )
    connectivity.sendArmingResult(ArmingResultPayload(alarmId: config.alarm.id, armedAt: Date(), status: status))
    connectivity.sendSessionResult(SessionResultPayload(
        alarmId: config.alarm.id,
        runId: runId,
        state: currentState,
        scheduledAt: runtimeLog.scheduledAt,
        failureReason: failureReason
    ))
}

func simulateRinging() {
    currentState = .ringing
    ringer.startRinging()
}

func snooze() {
    currentState = .snoozed
    ringer.snooze()
}

func stop() {
    currentState = .completed
    ringer.stop()
}
```

- [ ] **Step 4: Update Spike A and Spike B**

Append to `docs/spikes/Spike-A-watch-runtime-session.md`:

```markdown
## Runtime Session Adapter

The runtime-session adapter is `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`.
Simulator build verifies API compilation only. Real-device rows are required for background scheduling, lock-screen behavior, force-quit behavior, low battery behavior, disconnected phone behavior, and overnight behavior.
```

Append to `docs/spikes/Spike-B-alarm-channel-reliability.md`:

```markdown
## Watch Ringer Adapter

The Watch haptic adapter is `Apps/Watch/Sources/WatchAlarmRinger.swift`.
Simulator build verifies compile-time API usage only. Real-device rows are required for haptic strength, audible behavior, Silent Mode, Sleep Focus, locked screen, and app background state.
```

- [ ] **Step 5: Verify build and runtime log visibility**

Use XcodeBuildMCP `build_sim()` for `SmartSleepWatch`.

Expected:

- watchOS build succeeds.
- `WatchAppModel` can be constructed with `FakeRuntimeSessionScheduler(shouldSucceed: false)` and must report `runtime_session_not_scheduled`.
- A successful arm sends `SessionResultPayload` through the connectivity client.

- [ ] **Step 6: Commit**

Run:

```bash
git add Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift Apps/Watch/Sources/WatchAlarmRinger.swift Apps/Watch/Sources/WatchAppModel.swift docs/spikes/Spike-A-watch-runtime-session.md docs/spikes/Spike-B-alarm-channel-reliability.md
git commit -m "feat: add watch runtime and ringer adapters"
```

## Task 7: Update Real-Device Matrices and Dogfood Gate

**Files:**
- Modify: `docs/qa/device-test-matrix.md`
- Modify: `docs/qa/dogfood-runbook.md`

- [ ] **Step 1: Add integration matrix rows**

Append to `docs/qa/device-test-matrix.md`:

```markdown
| Connectivity | iPhone sends alarm config | Watch receives config and can arm | Requires paired real devices | Not tested |
| Connectivity | Watch sends arming result | iPhone status updates to Ready or Fallback | Requires paired real devices | Not tested |
| Runtime | Watch schedules runtime session | Runtime log records scheduled target start | Requires paired real devices | Not tested |
| Fallback | iPhone fallback notification scheduled | `AlarmChannelLog` records `iOSLocalNotification` | Simulator plus JSONL inspection | Not tested |
| Notification | iPhone fallback fires under Silent Mode and Sleep Focus | User notices fallback alarm | Requires paired real devices | Not tested |
| Ringer | Watch haptic feedback starts, snoozes, and stops | User can perceive haptic pattern on wrist | Requires paired real devices | Not tested |
| Export | AlarmRun JSONL export | Export contains state and channel events | Core test plus Simulator inspection | Not tested |
```

- [ ] **Step 2: Add dogfood execution gate**

Append to `docs/qa/dogfood-runbook.md`:

```markdown
## v0.2 Device Integration Gate

Before a dogfood run is counted as valid:

- iPhone and Apple Watch are paired to the same Apple ID.
- iPhone app has notification authorization.
- Watch app shows a received alarm config before arming.
- Watch arming failure with no config is recorded as `missing_alarm_config`.
- iPhone fallback channel is recorded as `iOSLocalNotification`.
- Exported JSONL contains at least one state transition and one channel event for the run.
- Runtime-session result is recorded as success or `runtime_session_not_scheduled`.
```

- [ ] **Step 3: Commit**

Run:

```bash
git add docs/qa/device-test-matrix.md docs/qa/dogfood-runbook.md
git commit -m "docs: add v02 device integration gates"
```

## Task 8: Final Verification for Device Integration

**Files:**
- Existing: all files modified by this plan

- [ ] **Step 1: Scan this plan for red flags**

Run:

```bash
rg -n "T[B]D|T[O]DO|impl[e]ment later|fill in d[e]tails|appropriate error h[a]ndling|handle edge c[a]ses|Similar t[o]" docs/superpowers/plans/2026-06-07-smartsleep-v02-device-integration-spikes.md
```

Expected: no matches.

- [ ] **Step 2: Run core tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all XCTest suites pass with 0 failures.

- [ ] **Step 3: Regenerate and build both targets**

Run:

```bash
xcodegen generate
```

Use XcodeBuildMCP `build_sim()` for `SmartSleepAlarm` and `SmartSleepWatch`.

Expected:

- Project generation succeeds.
- iOS build succeeds.
- watchOS build succeeds.

- [ ] **Step 4: Launch iOS Simulator for local visibility**

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

- Snapshot contains `SmartSleep`.
- Creating an alarm can produce visible fallback log JSON containing `iOSLocalNotification`.
- No claim is made that Simulator proves notification delivery or Watch delivery.

- [ ] **Step 5: Inspect git status**

Run:

```bash
git status --short
```

Expected: no generated artifacts are listed. Only intentional source and docs changes remain if commits were skipped.

## Self-Review

Spec coverage:

- Target pairing before `WCSession`: Task 2.
- Protocol-backed notification fallback and fake adapter: Task 3.
- Protocol-backed iOS `WCSession` and fake adapter: Task 4.
- Protocol-backed Watch `WCSession` and reactive UI: Task 5.
- Missing Watch config fails closed: Task 5.
- Runtime session protocol and fake adapter: Task 6.
- Watch ringer protocol and fake adapter: Task 6.
- Real-device matrices: Task 7.
- Critical-alert behavior kept out of v0.2 default path: Task 3 and Scope Boundaries.

Scope boundaries:

- Simulator builds do not prove real `WCSession` delivery.
- Simulator builds do not prove notification delivery under Silent Mode, Sleep Focus, lock screen, app termination, or low battery.
- Simulator builds do not prove Watch runtime-session reliability.
- Simulator builds do not prove Watch haptic/audio effectiveness.
- Critical-alert behavior requires entitlement, explicit authorization, Apple review, and product policy approval; it is not a default v0.2 channel.

Execution handoff:

- Do not start this plan until the app-state plan is complete.
- Every P0 adapter task must end with core tests where applicable, relevant target build, and visible log or matrix evidence.

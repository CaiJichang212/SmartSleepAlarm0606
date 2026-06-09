# SmartSleep v0.2 P0 Reliability Chain Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the next v0.2 development slice that turns the current core models and shell apps into a reliable P0 alarm chain with explicit fallback routing, editable alarms, runtime-driven Watch ringing, sensor freshness logging, and feature-flagged experiment hooks.

**Architecture:** Keep reliability decisions in `SmartSleepCore` so they can be tested without Apple frameworks. Keep iOS and watchOS Apple APIs behind small protocols with fake implementations in tests. Execute the plan in two phases: Phase A completes iOS fallback, CRUD, and logging; Phase B completes Watch runtime-window ringing, motion freshness, and feature-flagged experiments. The Watch runtime path owns `SESSION_SCHEDULED -> PRE_MONITORING -> RINGING`; automatic silence and re-sleep behavior remain disabled by default through `FeatureFlags.v02Default`.

**Tech Stack:** Swift 6.1, SwiftUI, XCTest, XcodeGen, WatchConnectivity, UserNotifications, WatchKit `WKExtendedRuntimeSession`, CoreMotion, optional AlarmKit guarded by availability, XcodeBuildMCP, paired iPhone + Apple Watch manual QA.

---

## Current Baseline

This plan starts from the current repository state after the audit:

- `SmartSleepCore` tests pass: 16 tests, 0 failures.
- Core models, state machine, `AwakeScorer`, `GestureSnoozeDetector`, JSONL event store, feature flags, iOS Local Notification scheduler, minimal `WCSession`, Watch arming, `WKExtendedRuntimeSession`, and basic Watch haptics exist.
- Real AlarmKit, real CoreMotion/HealthKit sampling, runtime-driven ring time, notification stop/snooze actions, re-sleep scoring, and user feedback UI are not complete.
- v0.2 scope rules still apply: no sleep reports, no cloud sync, no ML personalization, no audio recording, no Android, no medical claims, no workout-session workaround for heart-rate frequency.

Official Apple documentation to check while executing this plan:

- AlarmKit scheduling sample: https://developer.apple.com/documentation/AlarmKit/scheduling-an-alarm-with-alarmkit
- `AlarmManager.schedule(id:configuration:)`: https://developer.apple.com/documentation/alarmkit/alarmmanager/schedule%28id%3Aconfiguration%3A%29
- `WKExtendedRuntimeSession`: https://developer.apple.com/documentation/watchkit/wkextendedruntimesession
- CoreMotion: https://developer.apple.com/documentation/coremotion

## File Structure

```text
Packages/SmartSleepCore/Sources/SmartSleepCore/
  BackupChannelPolicy.swift          fallback channel selection and visible risk state
  ReSleepRiskScorer.swift            P0-Experiment risk score, still behind flags
  AlarmTimelinePlanner.swift         pre-monitor and ring-time timing decisions
  Models.swift                       add outcome values only if tests require them

Packages/SmartSleepCore/Tests/SmartSleepCoreTests/
  BackupChannelPolicyTests.swift
  ReSleepRiskScorerTests.swift
  AlarmTimelinePlannerTests.swift

Apps/iOS/Sources/
  AppModel.swift                     add update, enable/disable, feedback, fallback routing
  SmartSleepAlarmApp.swift           edit sheet, enable toggle, feedback controls
  BackupAlarmScheduler.swift         split local notification implementation and route by policy
  AlarmKitBackupAlarmScheduler.swift compile-gated AlarmKit adapter
  NotificationPermissionService.swift keep existing notification authorization behavior

Apps/iOS/Tests/
  AlarmDashboardModelTests.swift     extend model-level CRUD, routing, feedback tests
  BackupAlarmSchedulerTests.swift    extend scheduler routing tests

Apps/Watch/Sources/
  WatchAppModel.swift                wire runtime start, sensor freshness, ring-time state
  WatchRuntimeSessionScheduler.swift emit start/invalidation callbacks
  WatchAlarmRinger.swift             keep Watch haptic protocol; log channel events at model layer
  WatchAlarmRunLogger.swift          append runtime, channel, and sensor events from Watch
  WatchSensorSampler.swift           CoreMotion-backed sampler behind protocol
  WatchAlarmRunEngine.swift          runtime-driven pre-monitor and ringing coordinator

Apps/Watch/Tests/
  WatchAppModelTests.swift
  WatchAlarmRunLoggerTests.swift
  WatchAlarmRunEngineTests.swift
  WatchSensorSamplerTests.swift

docs/qa/
  device-test-matrix.md              add required manual device-test notes for Apple APIs
```

## Task 1: Add Core Fallback Channel Policy

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/BackupChannelPolicy.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/BackupChannelPolicyTests.swift`
- Modify: `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift`

- [ ] **Step 1: Write failing tests for fallback routing**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/BackupChannelPolicyTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class BackupChannelPolicyTests: XCTestCase {
    func testUsesAlarmKitWhenSupportedAndAuthorized() {
        let decision = BackupChannelPolicy().decision(
            preferred: .iOSAlarmKit,
            capabilities: BackupChannelCapabilities(
                alarmKitSupported: true,
                alarmKitAuthorization: .authorized,
                notificationAuthorization: .authorized,
                foregroundAudioAvailable: false
            )
        )

        XCTAssertEqual(decision.channel, .iOSAlarmKit)
        XCTAssertEqual(decision.userVisibleState, "alarmkit_ready")
        XCTAssertNil(decision.riskMessage)
        XCTAssertFalse(decision.requiresManualFallbackPrompt)
    }

    func testFallsBackToLocalNotificationWhenAlarmKitDenied() {
        let decision = BackupChannelPolicy().decision(
            preferred: .iOSAlarmKit,
            capabilities: BackupChannelCapabilities(
                alarmKitSupported: true,
                alarmKitAuthorization: .denied,
                notificationAuthorization: .authorized,
                foregroundAudioAvailable: false
            )
        )

        XCTAssertEqual(decision.channel, .iOSLocalNotification)
        XCTAssertEqual(decision.userVisibleState, "alarmkit_denied_local_notification")
        XCTAssertEqual(decision.riskMessage, "AlarmKit is denied; iPhone fallback uses Local Notification with lower reliability.")
        XCTAssertFalse(decision.requiresManualFallbackPrompt)
    }

    func testRequiresManualPromptWhenNoAutomaticFallbackIsAuthorized() {
        let decision = BackupChannelPolicy().decision(
            preferred: .iOSAlarmKit,
            capabilities: BackupChannelCapabilities(
                alarmKitSupported: false,
                alarmKitAuthorization: .unavailable,
                notificationAuthorization: .denied,
                foregroundAudioAvailable: false
            )
        )

        XCTAssertEqual(decision.channel, .manualFallbackPrompt)
        XCTAssertEqual(decision.userVisibleState, "manual_system_alarm_required")
        XCTAssertEqual(decision.riskMessage, "No automatic iPhone fallback is authorized; ask the user to set a system alarm.")
        XCTAssertTrue(decision.requiresManualFallbackPrompt)
    }

    func testSchedulerPolicyUsesFallbackPolicyDecision() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let decision = AlarmSchedulerPolicy().decision(
            for: alarm,
            arming: nil,
            capabilities: BackupChannelCapabilities(
                alarmKitSupported: true,
                alarmKitAuthorization: .authorized,
                notificationAuthorization: .authorized,
                foregroundAudioAvailable: false
            )
        )

        XCTAssertEqual(decision.smartModeStatus, .needsWatchArming)
        XCTAssertEqual(decision.requiredBackupChannel, .iOSAlarmKit)
        XCTAssertTrue(decision.shouldSchedulePhoneBackup)
        XCTAssertTrue(decision.shouldSyncToWatch)
    }

    func testDefaultSchedulerPolicyPreservesLocalNotificationFallback() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let decision = AlarmSchedulerPolicy().decision(for: alarm, arming: nil)

        XCTAssertEqual(decision.requiredBackupChannel, .iOSLocalNotification)
        XCTAssertEqual(decision.fallbackUserVisibleState, "notification_authorization_unknown")
        XCTAssertNil(decision.fallbackRiskMessage)
        XCTAssertFalse(decision.requiresManualFallbackPrompt)
    }
}
```

- [ ] **Step 2: Run the targeted failing test**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter BackupChannelPolicyTests
```

Expected: FAIL with compile errors for missing `BackupChannelPolicy`, `BackupChannelCapabilities`, and the new `AlarmSchedulerPolicy.decision(for:arming:capabilities:)` overload.

- [ ] **Step 3: Implement the policy**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/BackupChannelPolicy.swift`:

```swift
import Foundation

public struct BackupChannelCapabilities: Codable, Equatable, Sendable {
    public var alarmKitSupported: Bool
    public var alarmKitAuthorization: AuthorizationState
    public var notificationAuthorization: AuthorizationState
    public var foregroundAudioAvailable: Bool

    public init(
        alarmKitSupported: Bool,
        alarmKitAuthorization: AuthorizationState,
        notificationAuthorization: AuthorizationState,
        foregroundAudioAvailable: Bool
    ) {
        self.alarmKitSupported = alarmKitSupported
        self.alarmKitAuthorization = alarmKitAuthorization
        self.notificationAuthorization = notificationAuthorization
        self.foregroundAudioAvailable = foregroundAudioAvailable
    }

    public static let localNotificationDefault = BackupChannelCapabilities(
        alarmKitSupported: false,
        alarmKitAuthorization: .unavailable,
        notificationAuthorization: .unknown,
        foregroundAudioAvailable: false
    )
}

public struct BackupChannelDecision: Codable, Equatable, Sendable {
    public var channel: AlarmChannel
    public var userVisibleState: String
    public var riskMessage: String?
    public var requiresManualFallbackPrompt: Bool

    public init(
        channel: AlarmChannel,
        userVisibleState: String,
        riskMessage: String?,
        requiresManualFallbackPrompt: Bool
    ) {
        self.channel = channel
        self.userVisibleState = userVisibleState
        self.riskMessage = riskMessage
        self.requiresManualFallbackPrompt = requiresManualFallbackPrompt
    }
}

public struct BackupChannelPolicy: Sendable {
    public init() {}

    public func decision(
        preferred: AlarmChannel,
        capabilities: BackupChannelCapabilities
    ) -> BackupChannelDecision {
        if preferred == .iOSAlarmKit,
           capabilities.alarmKitSupported,
           capabilities.alarmKitAuthorization == .authorized {
            return BackupChannelDecision(
                channel: .iOSAlarmKit,
                userVisibleState: "alarmkit_ready",
                riskMessage: nil,
                requiresManualFallbackPrompt: false
            )
        }

        if capabilities.notificationAuthorization == .authorized ||
            capabilities.notificationAuthorization == .notDetermined ||
            capabilities.notificationAuthorization == .unknown {
            let state: String
            let message: String?
            if capabilities.notificationAuthorization == .authorized {
                state = capabilities.alarmKitSupported
                    ? "alarmkit_denied_local_notification"
                    : "alarmkit_unavailable_local_notification"
                message = capabilities.alarmKitSupported
                    ? "AlarmKit is denied; iPhone fallback uses Local Notification with lower reliability."
                    : "AlarmKit is unavailable on this device; iPhone fallback uses Local Notification with lower reliability."
            } else {
                state = "notification_authorization_unknown"
                message = nil
            }
            return BackupChannelDecision(
                channel: .iOSLocalNotification,
                userVisibleState: state,
                riskMessage: message,
                requiresManualFallbackPrompt: false
            )
        }

        if capabilities.foregroundAudioAvailable {
            return BackupChannelDecision(
                channel: .foregroundAudio,
                userVisibleState: "foreground_audio_only",
                riskMessage: "Notifications are denied; fallback audio works only while the iPhone app stays in foreground.",
                requiresManualFallbackPrompt: true
            )
        }

        return BackupChannelDecision(
            channel: .manualFallbackPrompt,
            userVisibleState: "manual_system_alarm_required",
            riskMessage: "No automatic iPhone fallback is authorized; ask the user to set a system alarm.",
            requiresManualFallbackPrompt: true
        )
    }
}
```

Modify `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift`:

```swift
import Foundation

public struct AlarmSchedulingDecision: Equatable, Sendable {
    public var smartModeStatus: SmartModeStatus
    public var shouldSyncToWatch: Bool
    public var shouldSchedulePhoneBackup: Bool
    public var requiredBackupChannel: AlarmChannel
    public var fallbackUserVisibleState: String
    public var fallbackRiskMessage: String?
    public var requiresManualFallbackPrompt: Bool

    public init(
        smartModeStatus: SmartModeStatus,
        shouldSyncToWatch: Bool,
        shouldSchedulePhoneBackup: Bool,
        requiredBackupChannel: AlarmChannel,
        fallbackUserVisibleState: String,
        fallbackRiskMessage: String?,
        requiresManualFallbackPrompt: Bool
    ) {
        self.smartModeStatus = smartModeStatus
        self.shouldSyncToWatch = shouldSyncToWatch
        self.shouldSchedulePhoneBackup = shouldSchedulePhoneBackup
        self.requiredBackupChannel = requiredBackupChannel
        self.fallbackUserVisibleState = fallbackUserVisibleState
        self.fallbackRiskMessage = fallbackRiskMessage
        self.requiresManualFallbackPrompt = requiresManualFallbackPrompt
    }
}

public struct AlarmSchedulerPolicy: Sendable {
    private let backupChannelPolicy: BackupChannelPolicy

    public init(backupChannelPolicy: BackupChannelPolicy = BackupChannelPolicy()) {
        self.backupChannelPolicy = backupChannelPolicy
    }

    public func decision(for alarm: Alarm, arming: WatchArmingStatus?) -> AlarmSchedulingDecision {
        decision(for: alarm, arming: arming, capabilities: .localNotificationDefault)
    }

    public func decision(
        for alarm: Alarm,
        arming: WatchArmingStatus?,
        capabilities: BackupChannelCapabilities
    ) -> AlarmSchedulingDecision {
        let status = SmartModeResolver.status(for: alarm, arming: arming)
        let fallback = backupChannelPolicy.decision(
            preferred: alarm.backupChannelPreferred,
            capabilities: capabilities
        )
        return AlarmSchedulingDecision(
            smartModeStatus: status,
            shouldSyncToWatch: alarm.isEnabled && alarm.smartEnabled,
            shouldSchedulePhoneBackup: alarm.isEnabled,
            requiredBackupChannel: fallback.channel,
            fallbackUserVisibleState: fallback.userVisibleState,
            fallbackRiskMessage: fallback.riskMessage,
            requiresManualFallbackPrompt: fallback.requiresManualFallbackPrompt
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter BackupChannelPolicyTests
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all `SmartSleepCore` tests pass. Existing `AlarmSchedulerPolicyTests` must preserve `.iOSLocalNotification` for `.localNotificationDefault`; do not let an unknown notification authorization state route to `.manualFallbackPrompt`.

- [ ] **Step 5: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/BackupChannelPolicy.swift Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmSchedulerPolicy.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/BackupChannelPolicyTests.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmSchedulerPolicyTests.swift
git commit -m "feat: add fallback channel policy"
```

## Task 2: Route iOS Backup Scheduling Through the Policy

**Files:**
- Modify: `Apps/iOS/Sources/BackupAlarmScheduler.swift`
- Modify: `Apps/iOS/Sources/AppModel.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`
- Modify: `Apps/iOS/Tests/BackupAlarmSchedulerTests.swift`
- Modify: `Apps/iOS/Tests/AlarmDashboardModelTests.swift`

- [ ] **Step 1: Write failing scheduler routing tests**

Append to `Apps/iOS/Tests/BackupAlarmSchedulerTests.swift`:

```swift
@MainActor
func testRoutingSchedulerRecordsManualFallbackWhenNoChannelIsAvailable() async throws {
    let scheduler = RoutingBackupAlarmScheduler(
        localNotificationScheduler: RecordingBackupAlarmScheduler(),
        alarmKitScheduler: RecordingBackupAlarmScheduler()
    )
    let alarm = Alarm.fixture(smartEnabled: true)
    let runId = UUID()

    let log = try await scheduler.scheduleBackup(
        for: alarm,
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        runId: runId,
        authorizationState: .denied,
        requiredChannel: .manualFallbackPrompt,
        userVisibleState: "manual_system_alarm_required"
    )

    XCTAssertEqual(log.channel, .manualFallbackPrompt)
    XCTAssertEqual(log.failureReason, "manual_fallback_required")
    XCTAssertEqual(log.userVisibleState, "manual_system_alarm_required")
}

@MainActor
func testRoutingSchedulerUsesAlarmKitSchedulerWhenRequired() async throws {
    let local = RecordingBackupAlarmScheduler()
    let alarmKit = RecordingBackupAlarmScheduler(recordedChannel: .iOSAlarmKit)
    let scheduler = RoutingBackupAlarmScheduler(
        localNotificationScheduler: local,
        alarmKitScheduler: alarmKit
    )
    let alarm = Alarm.fixture(smartEnabled: true)

    let log = try await scheduler.scheduleBackup(
        for: alarm,
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        runId: UUID(),
        authorizationState: .authorized,
        requiredChannel: .iOSAlarmKit,
        userVisibleState: "alarmkit_ready"
    )

    XCTAssertEqual(log.channel, .iOSAlarmKit)
    XCTAssertEqual(local.scheduledAlarmIDs, [])
    XCTAssertEqual(alarmKit.scheduledAlarmIDs, [alarm.id])
}
```

- [ ] **Step 2: Run targeted tests**

Run:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SmartSleepAlarmTests/BackupAlarmSchedulerTests
```

Expected: FAIL with missing `RoutingBackupAlarmScheduler`, missing `recordedChannel` initializer, and missing `scheduleBackup(... requiredChannel:userVisibleState:)`.

- [ ] **Step 3: Update the scheduler protocol and fake**

Modify `Apps/iOS/Sources/BackupAlarmScheduler.swift` so the protocol and fake become:

```swift
protocol BackupAlarmScheduling {
    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState,
        requiredChannel: AlarmChannel,
        userVisibleState: String
    ) async throws -> AlarmChannelLog
    func cancelBackup(for alarmId: UUID)
}

final class RecordingBackupAlarmScheduler: BackupAlarmScheduling {
    private(set) var scheduledAlarmIDs: [UUID] = []
    private(set) var cancelledAlarmIDs: [UUID] = []
    private let recordedChannel: AlarmChannel

    init(recordedChannel: AlarmChannel = .iOSLocalNotification) {
        self.recordedChannel = recordedChannel
    }

    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState,
        requiredChannel: AlarmChannel,
        userVisibleState: String
    ) async throws -> AlarmChannelLog {
        guard authorizationState == .authorized || requiredChannel == .iOSAlarmKit else {
            return AlarmChannelLog(
                runId: runId,
                channel: requiredChannel,
                scheduledAt: Date(),
                firedAt: nil,
                stoppedAt: nil,
                snoozedAt: nil,
                cancelledAt: nil,
                authorizationState: authorizationState,
                failureReason: "notification_not_authorized",
                userVisibleState: userVisibleState
            )
        }
        scheduledAlarmIDs.append(alarm.id)
        return AlarmChannelLog(
            runId: runId,
            channel: recordedChannel,
            scheduledAt: Date(),
            firedAt: nil,
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: authorizationState,
            failureReason: nil,
            userVisibleState: userVisibleState
        )
    }

    func cancelBackup(for alarmId: UUID) {
        cancelledAlarmIDs.append(alarmId)
    }
}
```

- [ ] **Step 4: Split local notification and routing scheduler**

In `Apps/iOS/Sources/BackupAlarmScheduler.swift`, rename the existing concrete scheduler to `LocalNotificationBackupAlarmScheduler` and replace its implementation with the full protocol-conforming version below. Keep the existing `Weekday.calendarWeekday` extension and request identifier helpers.

```swift
struct LocalNotificationBackupAlarmScheduler: BackupAlarmScheduling {
    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState,
        requiredChannel: AlarmChannel,
        userVisibleState: String
    ) async throws -> AlarmChannelLog {
        guard requiredChannel == .iOSLocalNotification else {
            return AlarmChannelLog(
                runId: runId,
                channel: requiredChannel,
                scheduledAt: Date(),
                firedAt: nil,
                stoppedAt: nil,
                snoozedAt: nil,
                cancelledAt: nil,
                authorizationState: authorizationState,
                failureReason: "local_notification_scheduler_wrong_channel",
                userVisibleState: userVisibleState
            )
        }

        guard authorizationState == .authorized else {
            return AlarmChannelLog(
                runId: runId,
                channel: .iOSLocalNotification,
                scheduledAt: Date(),
                firedAt: nil,
                stoppedAt: nil,
                snoozedAt: nil,
                cancelledAt: nil,
                authorizationState: authorizationState,
                failureReason: "notification_not_authorized",
                userVisibleState: userVisibleState
            )
        }

        let requests = Self.makeRequests(for: alarm, nextFireAt: nextFireAt)
        for request in requests {
            try await UNUserNotificationCenter.current().add(request)
        }

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
            userVisibleState: userVisibleState
        )
    }

    func cancelBackup(for alarmId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: Self.requestIdentifiers(for: alarmId)
        )
    }

    static func makeRequests(for alarm: Alarm, nextFireAt: Date) -> [UNNotificationRequest] {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "SmartSleep Alarm" : alarm.label
        content.body = "iPhone fallback alarm"
        content.sound = .default

        if alarm.repeatDays.isEmpty {
            var components = DateComponents()
            components.hour = Calendar.current.component(.hour, from: nextFireAt)
            components.minute = Calendar.current.component(.minute, from: nextFireAt)
            return [
                UNNotificationRequest(
                    identifier: requestIdentifier(for: alarm.id, weekday: nil),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
            ]
        }

        return alarm.repeatDays
            .sorted { $0.calendarWeekday < $1.calendarWeekday }
            .map { weekday in
                var components = DateComponents()
                components.hour = Calendar.current.component(.hour, from: nextFireAt)
                components.minute = Calendar.current.component(.minute, from: nextFireAt)
                components.weekday = weekday.calendarWeekday
                return UNNotificationRequest(
                    identifier: requestIdentifier(for: alarm.id, weekday: weekday),
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                )
            }
    }

    private static func requestIdentifiers(for alarmId: UUID) -> [String] {
        [requestIdentifier(for: alarmId, weekday: nil)] +
            Weekday.allCases.map { requestIdentifier(for: alarmId, weekday: $0) }
    }

    private static func requestIdentifier(for alarmId: UUID, weekday: Weekday?) -> String {
        if let weekday {
            return "backup-\(alarmId.uuidString)-\(weekday.rawValue)"
        }
        return "backup-\(alarmId.uuidString)"
    }
}
```

Add this routing scheduler below `LocalNotificationBackupAlarmScheduler`:

```swift
struct RoutingBackupAlarmScheduler: BackupAlarmScheduling {
    let localNotificationScheduler: BackupAlarmScheduling
    let alarmKitScheduler: BackupAlarmScheduling

    init(
        localNotificationScheduler: BackupAlarmScheduling = LocalNotificationBackupAlarmScheduler(),
        alarmKitScheduler: BackupAlarmScheduling = AlarmKitBackupAlarmScheduler()
    ) {
        self.localNotificationScheduler = localNotificationScheduler
        self.alarmKitScheduler = alarmKitScheduler
    }

    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState,
        requiredChannel: AlarmChannel,
        userVisibleState: String
    ) async throws -> AlarmChannelLog {
        switch requiredChannel {
        case .iOSAlarmKit:
            return try await alarmKitScheduler.scheduleBackup(
                for: alarm,
                nextFireAt: nextFireAt,
                runId: runId,
                authorizationState: authorizationState,
                requiredChannel: requiredChannel,
                userVisibleState: userVisibleState
            )
        case .iOSLocalNotification:
            return try await localNotificationScheduler.scheduleBackup(
                for: alarm,
                nextFireAt: nextFireAt,
                runId: runId,
                authorizationState: authorizationState,
                requiredChannel: requiredChannel,
                userVisibleState: userVisibleState
            )
        case .manualFallbackPrompt:
            return AlarmChannelLog(
                runId: runId,
                channel: .manualFallbackPrompt,
                scheduledAt: Date(),
                firedAt: nil,
                stoppedAt: nil,
                snoozedAt: nil,
                cancelledAt: nil,
                authorizationState: authorizationState,
                failureReason: "manual_fallback_required",
                userVisibleState: userVisibleState
            )
        case .foregroundAudio:
            return AlarmChannelLog(
                runId: runId,
                channel: .foregroundAudio,
                scheduledAt: Date(),
                firedAt: nil,
                stoppedAt: nil,
                snoozedAt: nil,
                cancelledAt: nil,
                authorizationState: authorizationState,
                failureReason: "foreground_audio_requires_open_app",
                userVisibleState: userVisibleState
            )
        case .watchRuntimeHapticAudio, .watchLocalNotification:
            return AlarmChannelLog(
                runId: runId,
                channel: requiredChannel,
                scheduledAt: Date(),
                firedAt: nil,
                stoppedAt: nil,
                snoozedAt: nil,
                cancelledAt: nil,
                authorizationState: .unavailable,
                failureReason: "not_an_iphone_backup_channel",
                userVisibleState: userVisibleState
            )
        }
    }

    func cancelBackup(for alarmId: UUID) {
        localNotificationScheduler.cancelBackup(for: alarmId)
        alarmKitScheduler.cancelBackup(for: alarmId)
    }
}

typealias BackupAlarmScheduler = RoutingBackupAlarmScheduler
```

Create the temporary compile-safe AlarmKit adapter in `Apps/iOS/Sources/AlarmKitBackupAlarmScheduler.swift`:

```swift
import Foundation
import SmartSleepCore

struct AlarmKitBackupAlarmScheduler: BackupAlarmScheduling {
    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState,
        requiredChannel: AlarmChannel,
        userVisibleState: String
    ) async throws -> AlarmChannelLog {
        guard authorizationState == .authorized else {
            return AlarmChannelLog(
                runId: runId,
                channel: .iOSAlarmKit,
                scheduledAt: Date(),
                firedAt: nil,
                stoppedAt: nil,
                snoozedAt: nil,
                cancelledAt: nil,
                authorizationState: authorizationState,
                failureReason: "alarmkit_not_authorized",
                userVisibleState: userVisibleState
            )
        }

        return AlarmChannelLog(
            runId: runId,
            channel: .iOSAlarmKit,
            scheduledAt: Date(),
            firedAt: nil,
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: authorizationState,
            failureReason: "alarmkit_adapter_not_enabled_in_this_build",
            userVisibleState: "alarmkit_compile_gated"
        )
    }

    func cancelBackup(for alarmId: UUID) {}
}
```

- [ ] **Step 5: Pass policy decision into scheduling**

In `Apps/iOS/Sources/AppModel.swift`, change the default scheduler from `BackupAlarmScheduler()` to `RoutingBackupAlarmScheduler()`. In `scheduleFallbackIfNeeded(for:runId:)`, call the scheduler with:

```swift
let capabilities = BackupChannelCapabilities(
    alarmKitSupported: false,
    alarmKitAuthorization: .unavailable,
    notificationAuthorization: authorizationState,
    foregroundAudioAvailable: false
)
let decision = schedulerPolicy.decision(for: item.alarm, arming: item.armingStatus, capabilities: capabilities)
let log = try await backupScheduler.scheduleBackup(
    for: item.alarm,
    nextFireAt: item.nextFireAt,
    runId: runId,
    authorizationState: authorizationState,
    requiredChannel: decision.requiredBackupChannel,
    userVisibleState: decision.fallbackUserVisibleState
)
```

When `decision.fallbackRiskMessage` is non-nil, set `userVisibleWarning` to that exact message after recording the log. When it is nil, preserve the existing `notification_not_authorized` warning behavior from `updateFallbackWarning(for:)`.

- [ ] **Step 6: Run tests and build**

Run:

```bash
xcodegen generate
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SmartSleepAlarmTests/BackupAlarmSchedulerTests
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SmartSleepAlarmTests/AlarmDashboardModelTests
```

Expected: targeted iOS tests pass. If `iPhone 16 Pro` is not installed, use XcodeBuildMCP `session_show_defaults()` first, then `list_sims(enabled: true)`, and select the newest installed iOS simulator.

- [ ] **Step 7: Add manual AlarmKit note**

Append to `docs/qa/device-test-matrix.md`:

```markdown
## AlarmKit Manual Device Note

AlarmKit is compile-gated in the current iOS build slice. Before enabling it as the default fallback on iOS 26+, verify on a real iPhone that:

- `NSAlarmKitUsageDescription` is present and user-readable.
- `AlarmManager.requestAuthorization()` returns `.authorized` after consent.
- A one-time alarm scheduled through `AlarmManager.schedule(id:configuration:)` alerts at the expected wall-clock time.
- Stop and snooze actions are reflected in `AlarmChannelLog`.
- If AlarmKit authorization is denied, `BackupChannelPolicy` routes to `iOSLocalNotification` or `manualFallbackPrompt`.
```

- [ ] **Step 8: Commit**

Run:

```bash
git add Apps/iOS/Sources/BackupAlarmScheduler.swift Apps/iOS/Sources/AlarmKitBackupAlarmScheduler.swift Apps/iOS/Sources/AppModel.swift Apps/iOS/Sources/SmartSleepAlarmApp.swift Apps/iOS/Tests/BackupAlarmSchedulerTests.swift Apps/iOS/Tests/AlarmDashboardModelTests.swift docs/qa/device-test-matrix.md
git commit -m "feat: route iphone fallback channels"
```

## Task 3: Complete iOS Alarm Editing and Enable/Disable Flow

**Files:**
- Modify: `Apps/iOS/Sources/AppModel.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`
- Modify: `Apps/iOS/Tests/AlarmDashboardModelTests.swift`

- [ ] **Step 1: Write failing model tests**

Append to `Apps/iOS/Tests/AlarmDashboardModelTests.swift`:

```swift
func testModelUpdatesExistingAlarmAndReschedulesFallback() async throws {
    let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
    let backupScheduler = RecordingBackupAlarmScheduler()
    let connectivity = FakePhoneConnectivityClient()
    let model = AlarmDashboardModel(
        repository: repository,
        notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
        backupScheduler: backupScheduler,
        connectivity: connectivity,
        runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
    )
    let original = AlarmCardState.make(
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        label: "Original",
        smartEnabled: true,
        snoozeMinutes: 9
    )

    await model.refreshNotificationAuthorization()
    model.create(original)
    await flushMainActorWork()

    let edited = AlarmCardState.make(
        id: original.id,
        nextFireAt: Date(timeIntervalSince1970: 7_200),
        label: "Edited",
        smartEnabled: false,
        snoozeMinutes: 12
    )
    model.update(edited)
    await flushMainActorWork()

    let persisted = try XCTUnwrap(repository.alarm(id: original.id))
    XCTAssertEqual(persisted.label, "Edited")
    XCTAssertFalse(persisted.smartEnabled)
    XCTAssertEqual(persisted.snoozeIntervalMin, 12)
    XCTAssertEqual(backupScheduler.cancelledAlarmIDs, [original.id])
    XCTAssertEqual(backupScheduler.scheduledAlarmIDs.last, original.id)
    XCTAssertTrue(connectivity.outboundOutbox.contains { message in
        guard case let .alarmCancelled(alarmId) = message else { return false }
        return alarmId == original.id
    })
}

func testDisablingAlarmCancelsFallbackAndWatchConfig() async throws {
    let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
    let backupScheduler = RecordingBackupAlarmScheduler()
    let connectivity = FakePhoneConnectivityClient()
    let model = AlarmDashboardModel(
        repository: repository,
        notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
        backupScheduler: backupScheduler,
        connectivity: connectivity,
        runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
    )
    let created = AlarmCardState.make(
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        label: "Disable Me",
        smartEnabled: true,
        snoozeMinutes: 9
    )

    await model.refreshNotificationAuthorization()
    model.create(created)
    await flushMainActorWork()
    model.setEnabled(false, alarmId: created.id)
    await flushMainActorWork()

    let persisted = try XCTUnwrap(repository.alarm(id: created.id))
    XCTAssertFalse(persisted.isEnabled)
    XCTAssertEqual(backupScheduler.cancelledAlarmIDs, [created.id])
    XCTAssertTrue(connectivity.outboundOutbox.contains { message in
        guard case let .alarmCancelled(alarmId) = message else { return false }
        return alarmId == created.id
    })
}
```

Add this overload to the test-only usage of `AlarmCardState.make` by planning the implementation in Step 3.

- [ ] **Step 2: Run targeted failing tests**

Run:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SmartSleepAlarmTests/AlarmDashboardModelTests/testModelUpdatesExistingAlarmAndReschedulesFallback -only-testing:SmartSleepAlarmTests/AlarmDashboardModelTests/testDisablingAlarmCancelsFallbackAndWatchConfig
```

Expected: FAIL with missing `update`, `setEnabled`, and `AlarmCardState.make(id:nextFireAt:label:smartEnabled:snoozeMinutes:)`.

- [ ] **Step 3: Implement model methods**

In `Apps/iOS/Sources/AppModel.swift`, add:

```swift
func update(_ alarm: AlarmCardState) {
    do {
        backupScheduler.cancelBackup(for: alarm.id)
        try repository.save(alarm.alarm)
        if !alarm.alarm.smartEnabled {
            connectivity.cancelAlarm(id: alarm.id)
        }
        reload()
        guard let persisted = alarms.first(where: { $0.id == alarm.id }) else { return }
        let runId = runIDs[alarm.id] ?? UUID()
        runIDs[alarm.id] = runId
        lastExportedRunID = runId
        scheduleFallbackIfNeeded(for: persisted, runId: runId)
        if persisted.alarm.smartEnabled && persisted.alarm.isEnabled {
            connectivity.sendAlarmConfig(AlarmConfigPayload(
                alarm: persisted.alarm,
                nextFireAt: persisted.nextFireAt
            ))
        }
    } catch {
        userVisibleWarning = "Failed to update alarm."
        exportedLogText = #"{"error":"failed_to_update_alarm"}"#
    }
}

func setEnabled(_ isEnabled: Bool, alarmId: UUID) {
    do {
        guard var alarm = try repository.alarm(id: alarmId) else { return }
        alarm.isEnabled = isEnabled
        alarm.updatedAt = Date()
        try repository.save(alarm)

        if isEnabled {
            reload()
            guard let persisted = alarms.first(where: { $0.id == alarmId }) else { return }
            let runId = runIDs[alarmId] ?? UUID()
            runIDs[alarmId] = runId
            lastExportedRunID = runId
            scheduleFallbackIfNeeded(for: persisted, runId: runId)
            if persisted.alarm.smartEnabled {
                connectivity.sendAlarmConfig(AlarmConfigPayload(
                    alarm: persisted.alarm,
                    nextFireAt: persisted.nextFireAt
                ))
            }
        } else {
            backupScheduler.cancelBackup(for: alarmId)
            connectivity.cancelAlarm(id: alarmId)
            reload()
        }
    } catch {
        userVisibleWarning = isEnabled ? "Failed to enable alarm." : "Failed to disable alarm."
    }
}
```

In `AlarmCardState`, add:

```swift
static func make(
    id: UUID,
    nextFireAt: Date,
    label: String,
    smartEnabled: Bool,
    snoozeMinutes: Int
) -> AlarmCardState {
    let components = Calendar.current.dateComponents([.hour, .minute], from: nextFireAt)
    let alarm = Alarm(
        id: id,
        timeOfDay: components,
        repeatDays: [],
        label: label.isEmpty ? "Alarm" : label,
        soundId: "default",
        isEnabled: true,
        smartEnabled: smartEnabled,
        requiresWatchArming: smartEnabled,
        snoozeIntervalMin: snoozeMinutes,
        maxSnoozeCount: 3,
        maxReAlarmCount: 2,
        backupChannelPreferred: .iOSLocalNotification
    )
    return AlarmCardState(id: id, alarm: alarm, armingStatus: nil, nextFireAt: nextFireAt)
}
```

Change the existing `make(nextFireAt:label:smartEnabled:snoozeMinutes:)` to call the new overload with `UUID()`. Keep `.iOSLocalNotification` as the default until the production AlarmKit adapter and authorization probe are complete; do not default new alarms to `.iOSAlarmKit` while Task 2 still reports `alarmKitSupported: false`.

- [ ] **Step 4: Add edit UI**

In `Apps/iOS/Sources/SmartSleepAlarmApp.swift`, replace `@State private var isCreatingAlarm = false` with:

```swift
@State private var editorAlarm: AlarmCardState?
```

Change the toolbar create button to:

```swift
Button {
    editorAlarm = AlarmCardState.make(
        nextFireAt: Date.now.addingTimeInterval(3600),
        label: "Morning",
        smartEnabled: true,
        snoozeMinutes: 9
    )
} label: {
    Label("新增闹铃", systemImage: "plus")
}
```

Add `.onTapGesture { editorAlarm = alarm }` to `AlarmCard(alarm: alarm)`.

Replace the sheet with:

```swift
.sheet(item: $editorAlarm) { alarm in
    EditAlarmView(alarm: alarm) { edited in
        if model.alarms.contains(where: { $0.id == edited.id }) {
            model.update(edited)
        } else {
            model.create(edited)
        }
    }
}
```

Rename `CreateAlarmView` to `EditAlarmView`, initialize its state from `alarm`, and add an enabled toggle:

```swift
private struct EditAlarmView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var nextFireAt: Date
    @State private var label: String
    @State private var isEnabled: Bool
    @State private var smartEnabled: Bool
    @State private var snoozeMinutes: Int

    let alarm: AlarmCardState
    let onSave: (AlarmCardState) -> Void

    init(alarm: AlarmCardState, onSave: @escaping (AlarmCardState) -> Void) {
        self.alarm = alarm
        self.onSave = onSave
        _nextFireAt = State(initialValue: alarm.nextFireAt)
        _label = State(initialValue: alarm.label)
        _isEnabled = State(initialValue: alarm.alarm.isEnabled)
        _smartEnabled = State(initialValue: alarm.alarm.smartEnabled)
        _snoozeMinutes = State(initialValue: alarm.alarm.snoozeIntervalMin)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("时间", selection: $nextFireAt, displayedComponents: .hourAndMinute)
                TextField("标签", text: $label)
                Toggle("启用", isOn: $isEnabled)
                Toggle("Smart Mode", isOn: $smartEnabled)
                Stepper("贪睡 \(snoozeMinutes) 分钟", value: $snoozeMinutes, in: 5...20)

                Section("就绪规则") {
                    LabeledContent("Watch 武装", value: smartEnabled ? "创建后需要确认" : "不需要")
                    LabeledContent("兜底通道", value: "iPhone 本地通知")
                }
            }
            .navigationTitle("闹铃")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var edited = AlarmCardState.make(
                            id: alarm.id,
                            nextFireAt: nextFireAt,
                            label: label,
                            smartEnabled: smartEnabled,
                            snoozeMinutes: snoozeMinutes
                        )
                        edited.alarm.isEnabled = isEnabled
                        edited.alarm.updatedAt = Date()
                        onSave(edited)
                        dismiss()
                    }
                }
            }
        }
    }
}
```

In `AlarmCard`, display disabled alarms explicitly:

```swift
if !alarm.alarm.isEnabled {
    Label("Disabled", systemImage: "power")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

- [ ] **Step 5: Run tests and build**

Run:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SmartSleepAlarmTests/AlarmDashboardModelTests
```

Use XcodeBuildMCP for a Simulator build:

```text
session_show_defaults()
list_schemes(projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj")
```

Then build `SmartSleepAlarm` for the active iOS Simulator. Expected: tests pass and build succeeds.

- [ ] **Step 6: Commit**

Run:

```bash
git add Apps/iOS/Sources/AppModel.swift Apps/iOS/Sources/SmartSleepAlarmApp.swift Apps/iOS/Tests/AlarmDashboardModelTests.swift
git commit -m "feat: complete alarm edit and enable flow"
```

## Task 4: Add Watch Runtime Logging

**Files:**
- Create: `Apps/Watch/Sources/WatchAlarmRunLogger.swift`
- Create: `Apps/Watch/Tests/WatchAlarmRunLoggerTests.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `Apps/Watch/Tests/WatchAppModelTests.swift`

- [ ] **Step 1: Write failing Watch logger tests**

Create `Apps/Watch/Tests/WatchAlarmRunLoggerTests.swift`:

```swift
import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchAlarmRunLoggerTests: XCTestCase {
    func testLoggerExportsRuntimeChannelAndFreshnessEvents() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let logger = try WatchAlarmRunLogger(logsDirectory: directory)
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
        try logger.recordChannel(AlarmChannelLog(
            runId: runId,
            channel: .watchRuntimeHapticAudio,
            scheduledAt: Date(timeIntervalSince1970: 20),
            firedAt: Date(timeIntervalSince1970: 20),
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: "ringing"
        ))
        try logger.recordFreshness(SensorFreshness(
            runId: runId,
            timestamp: Date(timeIntervalSince1970: 21),
            motionSampleCount: 20,
            motionLastSampleAgeSec: 1,
            hrSampleCount: 0,
            hrLastSampleAgeSec: nil,
            baselineHRConfidence: .none,
            baselineMotionConfidence: .medium,
            watchWornConfidence: .medium,
            sensorConfidence: .medium
        ))

        let exported = try logger.export(runId: runId)
        XCTAssertTrue(exported.contains("runtimeSession"))
        XCTAssertTrue(exported.contains("watchRuntimeHapticAudio"))
        XCTAssertTrue(exported.contains("sensorFreshness"))
    }
}
```

- [ ] **Step 2: Implement WatchAlarmRunLogger**

Create `Apps/Watch/Sources/WatchAlarmRunLogger.swift`:

```swift
import Foundation
import SmartSleepCore

protocol WatchAlarmRunLogging {
    func recordRuntimeSession(_ log: RuntimeSessionLog) throws
    func recordChannel(_ log: AlarmChannelLog) throws
    func recordFreshness(_ freshness: SensorFreshness) throws
    func recordGesture(_ gesture: GestureEvent) throws
    func recordOutcome(_ outcome: OutcomeLabel) throws
    func export(runId: UUID) throws -> String
}

struct WatchAlarmRunLogger: WatchAlarmRunLogging {
    let logsDirectory: URL

    init(logsDirectory: URL) throws {
        self.logsDirectory = logsDirectory
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    func recordRuntimeSession(_ log: RuntimeSessionLog) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.runtimeSession(log), recordedAt: log.actualStartAt ?? log.scheduledAt)
    }

    func recordChannel(_ log: AlarmChannelLog) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.channel(log), recordedAt: log.firedAt ?? log.scheduledAt)
    }

    func recordFreshness(_ freshness: SensorFreshness) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.sensorFreshness(freshness), recordedAt: freshness.timestamp)
    }

    func recordGesture(_ gesture: GestureEvent) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.gesture(gesture), recordedAt: gesture.timestamp)
    }

    func recordOutcome(_ outcome: OutcomeLabel) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.outcome(outcome), recordedAt: outcome.labeledAt)
    }

    func export(runId: UUID) throws -> String {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        return try store.export(runId: runId).joined(separator: "\n")
    }

    static func appStorage() throws -> WatchAlarmRunLogger {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try WatchAlarmRunLogger(logsDirectory: documents.appendingPathComponent("AlarmRuns", isDirectory: true))
    }

    static func temporary() -> WatchAlarmRunLogger {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("AlarmRuns", isDirectory: true)
        return try! WatchAlarmRunLogger(logsDirectory: directory)
    }
}

final class FakeWatchAlarmRunLogger: WatchAlarmRunLogging {
    private(set) var runtimeLogs: [RuntimeSessionLog] = []
    private(set) var channelLogs: [AlarmChannelLog] = []
    private(set) var freshnessLogs: [SensorFreshness] = []
    private(set) var gestureLogs: [GestureEvent] = []
    private(set) var outcomeLogs: [OutcomeLabel] = []

    func recordRuntimeSession(_ log: RuntimeSessionLog) throws { runtimeLogs.append(log) }
    func recordChannel(_ log: AlarmChannelLog) throws { channelLogs.append(log) }
    func recordFreshness(_ freshness: SensorFreshness) throws { freshnessLogs.append(freshness) }
    func recordGesture(_ gesture: GestureEvent) throws { gestureLogs.append(gesture) }
    func recordOutcome(_ outcome: OutcomeLabel) throws { outcomeLogs.append(outcome) }
    func export(runId: UUID) throws -> String { "" }
}
```

- [ ] **Step 3: Inject logger into WatchAppModel**

Add `runLogger: WatchAlarmRunLogging = WatchAlarmRunLogger.temporary()` to `WatchAppModel.init`. When `runtimeScheduler.schedule` returns, immediately call:

```swift
try? runLogger.recordRuntimeSession(runtimeLog)
```

In `handleRuntimeLogUpdate(_:)`, before state changes, call:

```swift
try? runLogger.recordRuntimeSession(log)
```

Later tasks must use this logger for channel and sensor events; do not add runtime, channel, or sensor logging as ad hoc print/debug output.

- [ ] **Step 4: Run tests**

Run:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -only-testing:SmartSleepWatchTests/WatchAlarmRunLoggerTests
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -only-testing:SmartSleepWatchTests/WatchAppModelTests
```

Expected: Watch logger tests pass, and existing Watch app model tests still pass after logger injection.

- [ ] **Step 5: Commit**

Run:

```bash
git add Apps/Watch/Sources/WatchAlarmRunLogger.swift Apps/Watch/Sources/WatchAppModel.swift Apps/Watch/Tests/WatchAlarmRunLoggerTests.swift Apps/Watch/Tests/WatchAppModelTests.swift
git commit -m "feat: add watch alarm run logging"
```

## Task 5: Add Runtime-Window Watch Ringing

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmTimelinePlanner.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmTimelinePlannerTests.swift`
- Create: `Apps/Watch/Sources/WatchAlarmRunEngine.swift`
- Create: `Apps/Watch/Tests/WatchAlarmRunEngineTests.swift`
- Modify: `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `Apps/Watch/Tests/WatchAppModelTests.swift`

- [ ] **Step 1: Write failing core timeline tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmTimelinePlannerTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class AlarmTimelinePlannerTests: XCTestCase {
    func testPreMonitoringStartsThirtyMinutesBeforeFireTime() {
        let fireAt = Date(timeIntervalSince1970: 3_600)
        let plan = AlarmTimelinePlanner().plan(nextFireAt: fireAt, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(plan.preMonitorTargetStartAt, Date(timeIntervalSince1970: 1_800))
        XCTAssertEqual(plan.secondsUntilRing, 3_600)
        XCTAssertFalse(plan.shouldStartRuntimeImmediately)
    }

    func testStartsImmediatelyWhenPreMonitoringWindowAlreadyOpened() {
        let fireAt = Date(timeIntervalSince1970: 3_600)
        let plan = AlarmTimelinePlanner().plan(nextFireAt: fireAt, now: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(plan.preMonitorTargetStartAt, Date(timeIntervalSince1970: 1_800))
        XCTAssertEqual(plan.secondsUntilRing, 1_600)
        XCTAssertTrue(plan.shouldStartRuntimeImmediately)
    }
}
```

- [ ] **Step 2: Implement timeline planner**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmTimelinePlanner.swift`:

```swift
import Foundation

public struct AlarmTimelinePlan: Codable, Equatable, Sendable {
    public var preMonitorTargetStartAt: Date
    public var secondsUntilRing: TimeInterval
    public var shouldStartRuntimeImmediately: Bool
}

public struct AlarmTimelinePlanner: Sendable {
    public var preMonitoringLeadTimeSec: TimeInterval

    public init(preMonitoringLeadTimeSec: TimeInterval = 30 * 60) {
        self.preMonitoringLeadTimeSec = preMonitoringLeadTimeSec
    }

    public func plan(nextFireAt: Date, now: Date) -> AlarmTimelinePlan {
        let targetStart = nextFireAt.addingTimeInterval(-preMonitoringLeadTimeSec)
        return AlarmTimelinePlan(
            preMonitorTargetStartAt: targetStart,
            secondsUntilRing: max(0, nextFireAt.timeIntervalSince(now)),
            shouldStartRuntimeImmediately: targetStart <= now
        )
    }
}
```

- [ ] **Step 3: Add runtime scheduler start callback**

Modify `RuntimeSessionScheduling` in `Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift`:

```swift
protocol RuntimeSessionScheduling: AnyObject {
    var latestLog: RuntimeSessionLog? { get }
    var onLogUpdated: ((RuntimeSessionLog) -> Void)? { get set }
    var onRuntimeStarted: ((RuntimeSessionLog) -> Void)? { get set }
    func schedule(for payload: AlarmConfigPayload, runId: UUID) -> RuntimeSessionLog
    func invalidate()
}
```

Add `var onRuntimeStarted: ((RuntimeSessionLog) -> Void)?` to both fake and real schedulers. In `extendedRuntimeSessionDidStart`, after `latestLog = log`, call:

```swift
onRuntimeStarted?(log)
```

In `FakeRuntimeSessionScheduler`, add:

```swift
func emitStart(_ log: RuntimeSessionLog) {
    latestLog = log
    onRuntimeStarted?(log)
}
```

- [ ] **Step 4: Write failing Watch engine tests**

Create `Apps/Watch/Tests/WatchAlarmRunEngineTests.swift`:

```swift
import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchAlarmRunEngineTests: XCTestCase {
    func testRuntimeStartMovesToPreMonitoringAndRingTimeStartsRingingInsideRuntimeWindow() {
        let ringer = FakeWatchAlarmRinger()
        let logger = FakeWatchAlarmRunLogger()
        let engine = WatchAlarmRunEngine(ringer: ringer)
        let runId = UUID()
        let log = RuntimeSessionLog(
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
        )

        engine.runtimeDidStart(log, nextFireAt: Date(timeIntervalSince1970: 20), runLogger: logger)
        XCTAssertEqual(engine.state, .preMonitoring)

        engine.ringTimeReached(runLogger: logger)
        XCTAssertEqual(engine.state, .ringing)
        XCTAssertEqual(ringer.startCallCount, 1)
        XCTAssertEqual(logger.channelLogs.last?.channel, .watchRuntimeHapticAudio)
        XCTAssertEqual(logger.channelLogs.last?.userVisibleState, "ringing")
    }
}
```

Update `FakeWatchAlarmRinger` in `Apps/Watch/Sources/WatchAlarmRinger.swift`:

```swift
final class FakeWatchAlarmRinger: WatchAlarmRinging {
    private(set) var startCallCount = 0
    private(set) var snoozeCallCount = 0
    private(set) var stopCallCount = 0

    func startRinging() {
        startCallCount += 1
    }

    func snooze() {
        snoozeCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}
```

- [ ] **Step 5: Implement WatchAlarmRunEngine**

Create `Apps/Watch/Sources/WatchAlarmRunEngine.swift`:

```swift
import Foundation
import SmartSleepCore

@MainActor
final class WatchAlarmRunEngine: ObservableObject {
    @Published private(set) var state: SmartAlarmState
    private let ringer: WatchAlarmRinging

    init(initialState: SmartAlarmState = .sessionScheduled, ringer: WatchAlarmRinging) {
        self.state = initialState
        self.ringer = ringer
    }

    private var activeRunId: UUID?

    func runtimeDidStart(
        _ log: RuntimeSessionLog,
        nextFireAt: Date,
        runLogger: WatchAlarmRunLogging
    ) {
        guard log.errorCode == nil, log.invalidatedAt == nil else {
            state = .fallbackPhoneAlarm
            return
        }
        activeRunId = log.runId
        state = .preMonitoring
    }

    func ringTimeReached(runLogger: WatchAlarmRunLogging, at date: Date = Date()) {
        guard state == .preMonitoring || state == .sessionScheduled else { return }
        state = .ringing
        ringer.startRinging()
        guard let activeRunId else { return }
        try? runLogger.recordChannel(AlarmChannelLog(
            runId: activeRunId,
            channel: .watchRuntimeHapticAudio,
            scheduledAt: date,
            firedAt: date,
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: "ringing"
        ))
    }

    func snooze() {
        guard state == .ringing || state == .reRinging else { return }
        state = .snoozed
        ringer.snooze()
    }

    func stop() {
        guard state == .ringing || state == .reRinging || state == .snoozed else { return }
        state = .completed
        ringer.stop()
    }
}
```

- [ ] **Step 6: Wire the engine into WatchAppModel**

In `WatchAppModel`, add:

```swift
private var runEngine: WatchAlarmRunEngine?
private var ringTask: Task<Void, Never>?
```

After a successful schedule in `armCurrentAlarm()`, create the engine but do not start a long-duration ring task:

```swift
if sessionScheduled {
    let engine = WatchAlarmRunEngine(initialState: .sessionScheduled, ringer: ringer)
    runEngine = engine
}
```

Set scheduler callback in `init`. The callback starts the ring timer only after the runtime session has actually started, so the app does not rely on an hours-long `Task.sleep` from the original Watch arming action:

```swift
self.runtimeScheduler.onRuntimeStarted = { [weak self] log in
    Task { @MainActor in
        guard let self, let config = self.lastConfig else { return }
        self.runEngine?.runtimeDidStart(log, nextFireAt: config.nextFireAt, runLogger: self.runLogger)
        if let state = self.runEngine?.state {
            self.currentState = state
        }
        let seconds = max(0, config.nextFireAt.timeIntervalSince(Date()))
        self.ringTask?.cancel()
        self.ringTask = Task { [weak self] in
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                guard let self else { return }
                self.runEngine?.ringTimeReached(runLogger: self.runLogger)
                if let state = self.runEngine?.state {
                    self.currentState = state
                }
            }
        }
    }
}
```

Cancel `ringTask` in `handleConfigChange(nil)`, `snooze()`, and `stop()`.

- [ ] **Step 7: Run tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter AlarmTimelinePlannerTests
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -only-testing:SmartSleepWatchTests/WatchAlarmRunEngineTests
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -only-testing:SmartSleepWatchTests/WatchAppModelTests
```

Expected: core timeline tests and Watch tests pass. Add a manual device-test note because `WKExtendedRuntimeSession.start(at:)` timing cannot be proven in Simulator. The implementation must not create a ring task at arming time for alarms that are hours away; the ring task is created only after runtime start.

- [ ] **Step 8: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/AlarmTimelinePlanner.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/AlarmTimelinePlannerTests.swift Apps/Watch/Sources/WatchRuntimeSessionScheduler.swift Apps/Watch/Sources/WatchAlarmRinger.swift Apps/Watch/Sources/WatchAlarmRunEngine.swift Apps/Watch/Sources/WatchAppModel.swift Apps/Watch/Tests/WatchAlarmRunEngineTests.swift Apps/Watch/Tests/WatchAppModelTests.swift
git commit -m "feat: drive watch ringing from runtime"
```

## Task 6: Add Watch Sensor Freshness Sampler

**Files:**
- Create: `Apps/Watch/Sources/WatchSensorSampler.swift`
- Create: `Apps/Watch/Tests/WatchSensorSamplerTests.swift`
- Modify: `Apps/Watch/Sources/WatchAppModel.swift`
- Modify: `docs/qa/device-test-matrix.md`

- [ ] **Step 1: Write fake sampler tests**

Create `Apps/Watch/Tests/WatchSensorSamplerTests.swift`:

```swift
import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchSensorSamplerTests: XCTestCase {
    func testFakeSamplerEmitsMotionFreshness() {
        let runId = UUID()
        let sampler = FakeWatchSensorSampler()
        var received: SensorFreshness?
        sampler.onFreshness = { received = $0 }

        sampler.start(runId: runId)
        sampler.emitFreshness(
            SensorFreshness(
                runId: runId,
                timestamp: Date(timeIntervalSince1970: 10),
                motionSampleCount: 30,
                motionLastSampleAgeSec: 1,
                hrSampleCount: 0,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                baselineMotionConfidence: .medium,
                watchWornConfidence: .medium,
                sensorConfidence: .medium
            )
        )

        XCTAssertEqual(received?.runId, runId)
        XCTAssertEqual(received?.motionLastSampleAgeSec, 1)
        XCTAssertTrue(received?.motionFresh == true)
    }
}
```

- [ ] **Step 2: Implement sampler protocol and fake**

Create `Apps/Watch/Sources/WatchSensorSampler.swift`:

```swift
import Foundation
import CoreMotion
import SmartSleepCore

protocol WatchSensorSampling: AnyObject {
    var onFreshness: ((SensorFreshness) -> Void)? { get set }
    var onSummary: ((SensorSummary) -> Void)? { get set }
    func start(runId: UUID)
    func stop()
}

final class FakeWatchSensorSampler: WatchSensorSampling {
    var onFreshness: ((SensorFreshness) -> Void)?
    var onSummary: ((SensorSummary) -> Void)?
    private(set) var activeRunId: UUID?

    func start(runId: UUID) {
        activeRunId = runId
    }

    func stop() {
        activeRunId = nil
    }

    func emitFreshness(_ freshness: SensorFreshness) {
        onFreshness?(freshness)
    }

    func emitSummary(_ summary: SensorSummary) {
        onSummary?(summary)
    }
}

final class CoreMotionWatchSensorSampler: WatchSensorSampling {
    var onFreshness: ((SensorFreshness) -> Void)?
    var onSummary: ((SensorSummary) -> Void)?

    private let motionManager = CMMotionManager()
    private var freshnessTask: Task<Void, Never>?
    private var runId: UUID?
    private var sampleCount = 0
    private var lastSampleAt: Date?
    private var windowStart: Date?
    private var gyroPeak: Double = 0
    private var accelValues: [Double] = []

    func start(runId: UUID) {
        self.runId = runId
        sampleCount = 0
        lastSampleAt = nil
        windowStart = Date()
        gyroPeak = 0
        accelValues = []

        motionManager.deviceMotionUpdateInterval = 0.2
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, let runId = self.runId else { return }
            let now = Date()
            self.sampleCount += 1
            self.lastSampleAt = now
            let accel = motion.userAcceleration
            let accelMagnitude = sqrt(accel.x * accel.x + accel.y * accel.y + accel.z * accel.z)
            self.accelValues.append(accelMagnitude)
            let rotation = motion.rotationRate
            let gyroMagnitude = sqrt(rotation.x * rotation.x + rotation.y * rotation.y + rotation.z * rotation.z)
            self.gyroPeak = max(self.gyroPeak, gyroMagnitude)

            let freshness = SensorFreshness(
                runId: runId,
                timestamp: now,
                motionSampleCount: self.sampleCount,
                motionLastSampleAgeSec: 0,
                hrSampleCount: 0,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                baselineMotionConfidence: self.sampleCount >= 10 ? .medium : .low,
                watchWornConfidence: .medium,
                sensorConfidence: self.sampleCount >= 10 ? .medium : .low
            )
            self.onFreshness?(freshness)
        }

        freshnessTask?.cancel()
        freshnessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    guard let self, let runId = self.runId else { return }
                    let now = Date()
                    let age = self.lastSampleAt.map { now.timeIntervalSince($0) } ?? .infinity
                    let confidence: ConfidenceLevel = age <= 2 ? .medium : .low
                    self.onFreshness?(SensorFreshness(
                        runId: runId,
                        timestamp: now,
                        motionSampleCount: self.sampleCount,
                        motionLastSampleAgeSec: age,
                        hrSampleCount: 0,
                        hrLastSampleAgeSec: nil,
                        baselineHRConfidence: .none,
                        baselineMotionConfidence: confidence,
                        watchWornConfidence: .medium,
                        sensorConfidence: confidence
                    ))
                }
            }
        }
    }

    func stop() {
        freshnessTask?.cancel()
        freshnessTask = nil
        motionManager.stopDeviceMotionUpdates()
        runId = nil
    }
}
```

- [ ] **Step 3: Wire sampler into WatchAppModel**

Add a `sensorSampler: WatchSensorSampling` dependency to `WatchAppModel.init`, defaulting to `CoreMotionWatchSensorSampler()`. When runtime starts, call:

```swift
if let activeRunID {
    sensorSampler.start(runId: activeRunID)
}
```

When config is removed, stopped, snoozed, or completed, call:

```swift
sensorSampler.stop()
```

Set:

```swift
self.sensorSampler.onFreshness = { [weak self] freshness in
    Task { @MainActor in
        guard let self else { return }
        try? self.runLogger.recordFreshness(freshness)
        let smartActiveStates: Set<SmartAlarmState> = [.preMonitoring, .ringing, .awakeCandidate, .reRinging]
        if !freshness.motionFresh && smartActiveStates.contains(self.currentState) {
            self.currentState = .ringingNoSmart
        }
    }
}
```

- [ ] **Step 4: Run tests and add manual note**

Run:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -only-testing:SmartSleepWatchTests/WatchSensorSamplerTests
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -only-testing:SmartSleepWatchTests/WatchAppModelTests
```

Append to `docs/qa/device-test-matrix.md`:

```markdown
## CoreMotion Manual Device Note

Simulator tests only verify sampler wiring. On a real Apple Watch, verify that:

- Device motion starts during `PRE_MONITORING`.
- `SensorFreshness.motionSampleCount` increases at least once per second.
- `motionLastSampleAgeSec > 2` is emitted by the stale tick and disables auto silence and gesture snooze without overwriting `completed`, `snoozed`, or `fallbackPhoneAlarm`.
- Left wrist and right wrist produce usable rotation samples.
- No HealthKit heart-rate sample is required for motion-only Smart Mode.
```

- [ ] **Step 5: Commit**

Run:

```bash
git add Apps/Watch/Sources/WatchSensorSampler.swift Apps/Watch/Sources/WatchAppModel.swift Apps/Watch/Tests/WatchSensorSamplerTests.swift Apps/Watch/Tests/WatchAppModelTests.swift docs/qa/device-test-matrix.md
git commit -m "feat: add watch motion freshness sampler"
```

## Task 7: Add Re-Sleep Risk Scorer Behind Feature Flags

**Files:**
- Create: `Packages/SmartSleepCore/Sources/SmartSleepCore/ReSleepRiskScorer.swift`
- Create: `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/ReSleepRiskScorerTests.swift`
- Modify: `Apps/Watch/Sources/WatchAlarmRunEngine.swift`
- Modify: `Apps/Watch/Tests/WatchAlarmRunEngineTests.swift`

- [ ] **Step 1: Write failing scorer tests**

Create `Packages/SmartSleepCore/Tests/SmartSleepCoreTests/ReSleepRiskScorerTests.swift`:

```swift
import XCTest
@testable import SmartSleepCore

final class ReSleepRiskScorerTests: XCTestCase {
    func testGracePeriodPreventsReRinging() {
        let result = ReSleepRiskScorer().evaluate(
            monitoringElapsedSec: 20,
            summary: SensorSummary.fixture(
                motionContinuitySec: 0,
                postureDelta: 1,
                gyroPeak: 0,
                stepDelta: 0,
                interactionCount: 0,
                hrDeltaFromBaseline: nil
            ),
            freshness: SensorFreshness.fixture(
                motionLastSampleAgeSec: 1,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                watchWornConfidence: .medium
            ),
            reAlarmCount: 0,
            maxReAlarmCount: 2
        )

        XCTAssertFalse(result.shouldReRing)
        XCTAssertTrue(result.reasonCodes.contains(.gracePeriod))
    }

    func testHighStillnessRiskTriggersAfterGracePeriod() {
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        summary.stillnessDurationSec = 150

        let result = ReSleepRiskScorer().evaluate(
            monitoringElapsedSec: 180,
            summary: summary,
            freshness: SensorFreshness.fixture(
                motionLastSampleAgeSec: 1,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                watchWornConfidence: .medium
            ),
            reAlarmCount: 0,
            maxReAlarmCount: 2
        )

        XCTAssertTrue(result.shouldReRing)
        XCTAssertGreaterThanOrEqual(result.riskScore, 0.8)
        XCTAssertTrue(result.reasonCodes.contains(.lowMotion))
        XCTAssertTrue(result.reasonCodes.contains(.noInteraction))
    }

    func testMaxReAlarmCountPreventsInfiniteReRinging() {
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        summary.stillnessDurationSec = 180

        let result = ReSleepRiskScorer().evaluate(
            monitoringElapsedSec: 240,
            summary: summary,
            freshness: SensorFreshness.fixture(
                motionLastSampleAgeSec: 1,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                watchWornConfidence: .medium
            ),
            reAlarmCount: 2,
            maxReAlarmCount: 2
        )

        XCTAssertFalse(result.shouldReRing)
        XCTAssertTrue(result.reasonCodes.contains(.maxReAlarmReached))
    }
}
```

- [ ] **Step 2: Implement scorer**

Create `Packages/SmartSleepCore/Sources/SmartSleepCore/ReSleepRiskScorer.swift`:

```swift
import Foundation

public enum ReSleepReasonCode: String, Codable, CaseIterable, Sendable {
    case gracePeriod
    case lowMotion
    case stablePosture
    case noInteraction
    case noSteps
    case heartRateReturnBoost
    case maxReAlarmReached
    case lowRisk
    case motionStale
}

public struct ReSleepRiskResult: Codable, Equatable, Sendable {
    public var riskScore: Double
    public var shouldReRing: Bool
    public var reasonCodes: Set<ReSleepReasonCode>
}

public struct ReSleepRiskScorer: Sendable {
    public var gracePeriodSec: Double
    public var highRiskThreshold: Double

    public init(gracePeriodSec: Double = 30, highRiskThreshold: Double = 0.8) {
        self.gracePeriodSec = gracePeriodSec
        self.highRiskThreshold = highRiskThreshold
    }

    public func evaluate(
        monitoringElapsedSec: Double,
        summary: SensorSummary,
        freshness: SensorFreshness,
        reAlarmCount: Int,
        maxReAlarmCount: Int
    ) -> ReSleepRiskResult {
        var score = 0.0
        var reasons: Set<ReSleepReasonCode> = []

        guard monitoringElapsedSec >= gracePeriodSec else {
            return ReSleepRiskResult(riskScore: 0, shouldReRing: false, reasonCodes: [.gracePeriod])
        }

        guard freshness.motionFresh else {
            return ReSleepRiskResult(riskScore: 0, shouldReRing: false, reasonCodes: [.motionStale])
        }

        if reAlarmCount >= maxReAlarmCount {
            return ReSleepRiskResult(riskScore: 0, shouldReRing: false, reasonCodes: [.maxReAlarmReached])
        }

        if summary.stillnessDurationSec >= 90 {
            score += 0.35
            reasons.insert(.lowMotion)
        }

        if summary.postureDelta < 10 {
            score += 0.20
            reasons.insert(.stablePosture)
        }

        if summary.interactionCount == 0 && summary.screenWakeCount == 0 {
            score += 0.20
            reasons.insert(.noInteraction)
        }

        if summary.stepDelta == 0 {
            score += 0.15
            reasons.insert(.noSteps)
        }

        if freshness.heartRateUsable, let hrDelta = summary.hrDeltaFromBaseline, hrDelta <= 3 {
            score += 0.10
            reasons.insert(.heartRateReturnBoost)
        }

        let risk = min(score, 1)
        let shouldReRing = risk >= highRiskThreshold
        if !shouldReRing {
            reasons.insert(.lowRisk)
        }

        return ReSleepRiskResult(riskScore: risk, shouldReRing: shouldReRing, reasonCodes: reasons)
    }
}
```

- [ ] **Step 3: Wire only behind flags**

In `WatchAlarmRunEngine`, add:

```swift
private let featureFlags: FeatureFlags
private let reSleepScorer: ReSleepRiskScorer
private var reAlarmCount = 0
private var silencedAt: Date?
```

Update the initializer to accept `featureFlags: FeatureFlags = .v02Default` and `reSleepScorer: ReSleepRiskScorer = ReSleepRiskScorer()`.

Add:

```swift
func autoSilenceConfirmed(at date: Date = Date()) {
    guard featureFlags.autoSilenceEnabled else { return }
    state = .silencedMonitoring
    silencedAt = date
}

func evaluateReSleep(summary: SensorSummary, freshness: SensorFreshness, now: Date = Date()) -> ReSleepRiskResult? {
    guard featureFlags.reSleepDetectionEnabled, state == .silencedMonitoring, let silencedAt else { return nil }
    let result = reSleepScorer.evaluate(
        monitoringElapsedSec: now.timeIntervalSince(silencedAt),
        summary: summary,
        freshness: freshness,
        reAlarmCount: reAlarmCount,
        maxReAlarmCount: featureFlags.maxReAlarmCount
    )
    if result.shouldReRing {
        reAlarmCount += 1
        state = .reRinging
        ringer.startRinging()
    }
    return result
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore --filter ReSleepRiskScorerTests
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' -only-testing:SmartSleepWatchTests/WatchAlarmRunEngineTests
```

Expected: scorer tests pass; Watch engine tests prove re-sleep does nothing with default flags and re-rings only when flags are explicitly enabled in test.

- [ ] **Step 5: Commit**

Run:

```bash
git add Packages/SmartSleepCore/Sources/SmartSleepCore/ReSleepRiskScorer.swift Packages/SmartSleepCore/Tests/SmartSleepCoreTests/ReSleepRiskScorerTests.swift Apps/Watch/Sources/WatchAlarmRunEngine.swift Apps/Watch/Tests/WatchAlarmRunEngineTests.swift
git commit -m "feat: add flagged re-sleep risk scorer"
```

## Task 8: Add User Outcome Feedback and Log Export Flow

**Files:**
- Modify: `Apps/iOS/Sources/AlarmRunLogger.swift`
- Modify: `Apps/iOS/Sources/AppModel.swift`
- Modify: `Apps/iOS/Sources/SmartSleepAlarmApp.swift`
- Modify: `Apps/iOS/Tests/AlarmDashboardModelTests.swift`

- [ ] **Step 1: Write failing feedback test**

Append to `Apps/iOS/Tests/AlarmDashboardModelTests.swift`:

```swift
func testModelRecordsOutcomeFeedbackForLastRun() async throws {
    let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
    let logsDirectory = temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true)
    let model = AlarmDashboardModel(
        repository: repository,
        notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
        backupScheduler: RecordingBackupAlarmScheduler(),
        runLogger: AlarmRunLogger(logsDirectory: logsDirectory)
    )
    let created = AlarmCardState.make(
        nextFireAt: Date(timeIntervalSince1970: 3_600),
        label: "Feedback",
        smartEnabled: true,
        snoozeMinutes: 9
    )

    await model.refreshNotificationAuthorization()
    model.create(created)
    await flushMainActorWork()
    model.recordFeedback(.falseSilence, notes: "Detected while still asleep.")

    XCTAssertTrue(model.exportedLogText.contains("outcome"))
    XCTAssertTrue(model.exportedLogText.contains("\"falseSilenceReported\":true"))
    XCTAssertTrue(model.exportedLogText.contains("Detected while still asleep."))
}
```

- [ ] **Step 2: Add logger support**

Modify `Apps/iOS/Sources/AlarmRunLogger.swift`:

```swift
protocol AlarmRunLogging {
    func recordAlarmCreated(runId: UUID) throws
    func recordChannelLog(_ log: AlarmChannelLog) throws
    func recordOutcome(_ outcome: OutcomeLabel) throws
    func export(runId: UUID) throws -> String
}

func recordOutcome(_ outcome: OutcomeLabel) throws {
    let store = try JSONLAlarmEventStore(directory: logsDirectory)
    try store.append(.outcome(outcome), recordedAt: outcome.labeledAt)
}
```

- [ ] **Step 3: Add model feedback method**

In `AlarmDashboardModel`, add:

```swift
func recordFeedback(_ outcome: OutcomeKind, notes: String?) {
    guard let lastExportedRunID else {
        userVisibleWarning = "No alarm run is available for feedback."
        return
    }
    let label = OutcomeLabel(
        runId: lastExportedRunID,
        manualStop: outcome == .userStopped,
        manualSnooze: outcome == .userSnoozed,
        gestureSnooze: false,
        autoSilenceAccepted: outcome == .wokeUp,
        falseSilenceReported: outcome == .falseSilence,
        falseReAlarmReported: outcome == .falseReAlarm,
        missedAlarmReported: outcome == .missedAlarm,
        fallbackUsed: false,
        userReportedStillAsleep: outcome == .falseSilence,
        userReportedAwake: outcome == .wokeUp || outcome == .falseReAlarm,
        notes: notes,
        labeledAt: Date()
    )
    do {
        try runLogger.recordOutcome(label)
        exportedLogText = (try? runLogger.export(runId: lastExportedRunID)) ?? ""
    } catch {
        userVisibleWarning = "Failed to record feedback."
    }
}
```

- [ ] **Step 4: Add internal feedback UI**

In `SmartSleepAlarmApp.swift`, add to the internal testing section:

```swift
Button {
    model.recordFeedback(.wokeUp, notes: "User reported awake during dogfood.")
} label: {
    Label("标注：已醒", systemImage: "checkmark.circle")
}

Button {
    model.recordFeedback(.falseSilence, notes: "User reported false silence during dogfood.")
} label: {
    Label("标注：误静音", systemImage: "exclamationmark.circle")
}

Button {
    model.recordFeedback(.falseReAlarm, notes: "User reported false re-alarm during dogfood.")
} label: {
    Label("标注：误重响", systemImage: "bell.badge")
}

Button {
    model.recordFeedback(.missedAlarm, notes: "User reported missed alarm during dogfood.")
} label: {
    Label("标注：没响", systemImage: "xmark.octagon")
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:SmartSleepAlarmTests/AlarmDashboardModelTests/testModelRecordsOutcomeFeedbackForLastRun
```

Expected: feedback test passes and exported JSONL includes an `outcome` record.

- [ ] **Step 6: Commit**

Run:

```bash
git add Apps/iOS/Sources/AlarmRunLogger.swift Apps/iOS/Sources/AppModel.swift Apps/iOS/Sources/SmartSleepAlarmApp.swift Apps/iOS/Tests/AlarmDashboardModelTests.swift
git commit -m "feat: record dogfood outcome feedback"
```

## Task 9: Final Verification and Device QA Gate

**Files:**
- Modify: `docs/qa/dogfood-runbook.md`
- Modify: `docs/qa/device-test-matrix.md`

- [ ] **Step 1: Run pure Swift tests**

Run:

```bash
env SWIFTPM_HOME="$PWD/.build/swiftpm-home" CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" swift test --package-path Packages/SmartSleepCore
```

Expected: all `SmartSleepCore` tests pass.

- [ ] **Step 2: Run iOS and Watch tests**

Run:

```bash
xcodegen generate
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepAlarm -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild test -project SmartSleepAlarm.xcodeproj -scheme SmartSleepWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)'
```

Expected: iOS and Watch test targets pass. If simulator names differ, use XcodeBuildMCP `list_sims` and rerun with installed simulator names.

- [ ] **Step 3: Build both app targets with XcodeBuildMCP**

Use XcodeBuildMCP:

```text
session_show_defaults()
list_schemes(projectPath: "/Users/lzc/TNTprojectZ/AprojectZ/SmartSleepAlarm/SmartSleepAlarm.xcodeproj")
```

Build `SmartSleepAlarm` and `SmartSleepWatch` for Simulator. Expected: both builds return `SUCCEEDED`.

- [ ] **Step 4: Update dogfood runbook**

Append to `docs/qa/dogfood-runbook.md`:

```markdown
## P0 Reliability Chain Gate

Before enabling auto silence or re-sleep detection for dogfood, complete this sequence on paired real devices:

1. Create an iPhone alarm with Smart Mode on.
2. Confirm the iPhone card shows `Needs Watch Arming`.
3. Arm the alarm on Watch.
4. Confirm the iPhone card shows `Ready` only after Watch reports `sessionScheduled == true`.
5. Confirm iPhone fallback channel log is written before the alarm time.
6. Confirm Watch enters `PRE_MONITORING` after runtime start.
7. Confirm Watch enters `RINGING` at the scheduled alarm time without pressing the dogfood simulate button.
8. Confirm stopping or snoozing records an outcome or channel event.
9. Deny notification authorization and confirm the app shows a manual fallback prompt instead of implying reliable Smart Mode.
10. Export JSONL and verify state transition, channel, runtime, sensor freshness, and outcome records are present.
```

- [ ] **Step 5: Update device matrix**

Append to `docs/qa/device-test-matrix.md`:

```markdown
## P0 Reliability Chain Required Results

| Scenario | Required result | Required log |
|---|---|---|
| Watch armed and session scheduled | iPhone shows Ready | `armingResult` and `RuntimeSessionLog` |
| Watch session invalidated | iPhone shows Fallback Only | `RuntimeSessionLog.invalidationReason` |
| AlarmKit unavailable | Local Notification or manual prompt shown | `AlarmChannelLog.channel` |
| Notification denied | Manual fallback prompt shown | `authorizationState: denied` |
| Runtime starts before alarm | Watch enters PRE_MONITORING | `preMonitorActualStartAt` or runtime actual start |
| Motion stale | Auto silence and gesture disabled | `SensorFreshness.motionLastSampleAgeSec` |
| User reports false silence | Outcome exported | `OutcomeLabel.falseSilenceReported` |
```

- [ ] **Step 6: Commit**

Run:

```bash
git add docs/qa/dogfood-runbook.md docs/qa/device-test-matrix.md
git commit -m "docs: add p0 reliability qa gate"
```

## Self-Review

Spec coverage:

- FR-1 iOS alarm management: Task 3 covers edit and enable/disable. Existing create/delete/list remain in place.
- FR-2 Watch arming and readiness: Task 5 keeps Ready tied to session scheduling and adds runtime-window ring path.
- FR-3 Watch pre-monitoring: Task 5 adds runtime start to `PRE_MONITORING`; Task 6 adds motion freshness sampling.
- FR-4 Ringing and iPhone fallback: Task 1 and Task 2 add explicit fallback routing; Task 5 drives Watch ringing from the runtime window.
- FR-5 Auto silence: This plan does not enable auto silence by default. Existing `AwakeScorer` remains the pure logic layer, and Task 6 provides motion freshness required before wiring two-stage confirmation.
- FR-6 Re-sleep risk: Task 7 adds scorer and keeps it behind feature flags.
- FR-7 Gesture snooze: Existing `GestureSnoozeDetector` remains pure logic. Real-time CoreMotion integration is partially prepared by Task 6, but final gesture stream wiring should be a follow-up slice after motion device thresholds are measured.
- FR-8 Degradation: Task 1 and Task 2 cover AlarmKit/notification/manual fallback; Task 6 covers motion stale behavior.
- FR-9 Logs and feedback: Task 4 adds Watch runtime/channel/sensor logging and Task 8 adds outcome feedback and export.
- FR-10 Privacy and compliance: Task 9 adds manual QA gate notes. Full privacy copy and local history deletion remain a separate compliance slice.

Residual gaps intentionally left for the next plan:

- Full AlarmKit production adapter with App Intents and `NSAlarmKitUsageDescription` after confirming the installed Xcode SDK exposes AlarmKit APIs.
- HealthKit heart-rate freshness adapter.
- Two-stage auto-silence coordinator that consumes live sensor windows.
- Real-time gesture stream wiring and threshold tuning.
- Local history deletion UI and final TestFlight privacy copy.

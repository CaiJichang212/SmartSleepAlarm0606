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
        var alarm = Alarm.fixture(smartEnabled: true)
        alarm.backupChannelPreferred = .iOSAlarmKit
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

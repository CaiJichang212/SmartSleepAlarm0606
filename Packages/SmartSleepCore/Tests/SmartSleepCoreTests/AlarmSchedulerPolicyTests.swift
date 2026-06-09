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

    func testDefaultFallbackDecisionUsesUnknownNotificationState() {
        let alarm = Alarm.fixture(smartEnabled: true)
        let decision = AlarmSchedulerPolicy().decision(for: alarm, arming: nil)

        XCTAssertEqual(decision.fallbackUserVisibleState, "notification_authorization_unknown")
        XCTAssertNil(decision.fallbackRiskMessage)
        XCTAssertFalse(decision.requiresManualFallbackPrompt)
    }
}

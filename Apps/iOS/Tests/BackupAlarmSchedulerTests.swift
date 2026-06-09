import XCTest
@testable import SmartSleepAlarm
import SmartSleepCore

final class BackupAlarmSchedulerTests: XCTestCase {
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
        XCTAssertEqual(alarmKit.scheduledChannels, [.iOSAlarmKit])
    }

    func testRepeatingAlarmBuildsOneRequestPerWeekday() throws {
        var alarm = Alarm.fixture(smartEnabled: true)
        alarm.repeatDays = [.monday, .wednesday, .friday]
        let nextFireAt = Date(timeIntervalSince1970: 3_600)

        let requests = BackupAlarmScheduler.makeRequests(for: alarm, nextFireAt: nextFireAt)

        XCTAssertEqual(requests.count, 3)
        let weekdays = requests.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?
                .dateComponents
                .weekday
        }
        XCTAssertEqual(Set(weekdays), Set([2, 4, 6]))
    }

    func testNonRepeatingAlarmBuildsSingleRequestWithoutWeekday() throws {
        var alarm = Alarm.fixture(smartEnabled: true)
        alarm.repeatDays = []
        let nextFireAt = Date(timeIntervalSince1970: 3_600)
        let expectedComponents = Calendar.current.dateComponents([.hour, .minute], from: nextFireAt)

        let requests = BackupAlarmScheduler.makeRequests(for: alarm, nextFireAt: nextFireAt)

        XCTAssertEqual(requests.count, 1)
        let components = try XCTUnwrap((requests[0].trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        XCTAssertNil(components.weekday)
        XCTAssertEqual(components.hour, expectedComponents.hour)
        XCTAssertEqual(components.minute, expectedComponents.minute)
    }
}

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

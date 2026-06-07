import XCTest
@testable import SmartSleepAlarm
import SmartSleepCore

@MainActor
final class AlarmDashboardModelTests: XCTestCase {
    func testModelSeedsEmptyRepositoryUsingLocalNotificationFallback() throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())

        let model = AlarmDashboardModel(repository: repository)

        XCTAssertEqual(model.alarms.count, AlarmCardState.seed.count)
        XCTAssertNil(model.userVisibleWarning)
        XCTAssertTrue(model.alarms.allSatisfy { $0.alarm.backupChannelPreferred == .iOSLocalNotification })
        XCTAssertEqual(try repository.list().count, AlarmCardState.seed.count)
    }

    func testModelCreateDeleteAndPreviewUsePersistedLocalNotificationChannel() throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
        let model = AlarmDashboardModel(repository: repository)
        let created = AlarmCardState.make(
            nextFireAt: Date(timeIntervalSince1970: 3_600),
            label: "Created",
            smartEnabled: true,
            snoozeMinutes: 9
        )

        model.create(created)

        XCTAssertEqual(try repository.alarm(id: created.id)?.backupChannelPreferred, .iOSLocalNotification)

        model.exportPreview()
        XCTAssertTrue(model.exportedLogText.contains("iOSLocalNotification"))
        XCTAssertFalse(model.exportedLogText.contains("iOSAlarmKit"))

        guard let index = model.alarms.firstIndex(where: { $0.id == created.id }) else {
            return XCTFail("expected created alarm to be present")
        }

        model.delete(at: IndexSet(integer: index))
        XCTAssertNil(try repository.alarm(id: created.id))
    }

    func testModelShowsWarningForUnreadableRepositoryData() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)
        let repository = AlarmFileRepositoryAdapter(fileURL: fileURL)

        let model = AlarmDashboardModel(repository: repository)

        XCTAssertEqual(model.userVisibleWarning, "Failed to load alarms.")
        XCTAssertEqual(model.alarms, [])
    }

    private func temporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("alarms.json")
    }
}

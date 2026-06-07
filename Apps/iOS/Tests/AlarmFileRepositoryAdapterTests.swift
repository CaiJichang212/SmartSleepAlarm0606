import XCTest
@testable import SmartSleepAlarm
import SmartSleepCore

final class AlarmFileRepositoryAdapterTests: XCTestCase {
    func testFileRepositoryPersistsSortedCreateUpdateDeleteLifecycle() throws {
        let fileURL = temporaryFileURL()
        let repository = AlarmFileRepositoryAdapter(fileURL: fileURL)

        var later = Alarm.fixture(smartEnabled: true)
        later.timeOfDay = DateComponents(hour: 8, minute: 15)
        later.backupChannelPreferred = .iOSLocalNotification

        var earlier = Alarm.fixture(smartEnabled: true)
        earlier.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        earlier.timeOfDay = DateComponents(hour: 6, minute: 45)
        earlier.backupChannelPreferred = .iOSLocalNotification

        try repository.save(later)
        try repository.save(earlier)

        XCTAssertEqual(try repository.list().map(\.id), [earlier.id, later.id])
        XCTAssertEqual(try repository.alarm(id: later.id)?.backupChannelPreferred, .iOSLocalNotification)

        var updated = later
        updated.isEnabled = false
        try repository.save(updated)
        XCTAssertEqual(try repository.alarm(id: later.id)?.isEnabled, false)

        try repository.delete(id: earlier.id)
        XCTAssertEqual(try repository.list().map(\.id), [later.id])
    }

    func testFileRepositoryThrowsForInvalidJSONPayload() throws {
        let fileURL = temporaryFileURL()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: fileURL, options: .atomic)
        let repository = AlarmFileRepositoryAdapter(fileURL: fileURL)

        XCTAssertThrowsError(try repository.list())
    }

    func testLogExportServiceExportsJSONLLines() throws {
        let directory = temporaryDirectoryURL()
        let runId = UUID()
        let store = try JSONLAlarmEventStore(directory: directory)
        try store.append(.stateTransition(StateTransitionLog(
            runId: runId,
            fromState: .idle,
            toState: .needsWatchArming,
            timestamp: Date(timeIntervalSince1970: 10),
            reason: "created_on_phone",
            confidence: nil,
            featureSnapshotId: nil,
            errorCode: nil
        )))

        let service = LogExportService(logsDirectory: directory)
        let exported = try service.export(runId: runId)

        XCTAssertTrue(exported.contains("created_on_phone"))
        XCTAssertTrue(exported.contains("stateTransition"))
    }

    private func temporaryFileURL() -> URL {
        temporaryDirectoryURL().appendingPathComponent("alarms.json")
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

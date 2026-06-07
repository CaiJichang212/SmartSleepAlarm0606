import XCTest
@testable import SmartSleepAlarm
import SmartSleepCore

@MainActor
final class AlarmDashboardModelTests: XCTestCase {
    func testModelExportsStateAndChannelEventsForFallbackRun() async throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
        let logsDirectory = temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true)
        let backupScheduler = RecordingBackupAlarmScheduler()
        let model = AlarmDashboardModel(
            repository: repository,
            notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
            backupScheduler: backupScheduler,
            runLogger: AlarmRunLogger(logsDirectory: logsDirectory)
        )
        let created = AlarmCardState.make(
            nextFireAt: Date(timeIntervalSince1970: 3_600),
            label: "Created",
            smartEnabled: true,
            snoozeMinutes: 9
        )

        await model.refreshNotificationAuthorization()
        model.create(created)
        await flushMainActorWork()

        XCTAssertTrue(model.exportedLogText.contains("stateTransition"))
        XCTAssertTrue(model.exportedLogText.contains("channel"))
        XCTAssertTrue(model.exportedLogText.contains("created_on_phone"))
        XCTAssertTrue(model.exportedLogText.contains("iOSLocalNotification"))
    }

    func testModelDeniedNotificationAuthorizationExportsFailureLogAndWarning() async throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
        let logsDirectory = temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true)
        let backupScheduler = RecordingBackupAlarmScheduler()
        let model = AlarmDashboardModel(
            repository: repository,
            notificationAuthorizer: FakeNotificationAuthorizer(state: .denied),
            backupScheduler: backupScheduler,
            runLogger: AlarmRunLogger(logsDirectory: logsDirectory)
        )
        let created = AlarmCardState.make(
            nextFireAt: Date(timeIntervalSince1970: 3_600),
            label: "Denied",
            smartEnabled: true,
            snoozeMinutes: 9
        )

        await model.refreshNotificationAuthorization()
        model.create(created)
        await flushMainActorWork()

        XCTAssertTrue(model.exportedLogText.contains("notification_not_authorized"))
        XCTAssertTrue(model.exportedLogText.contains("\"authorizationState\":\"denied\""))
        XCTAssertEqual(model.userVisibleWarning, "iPhone fallback notifications are not authorized.")
        XCTAssertTrue(backupScheduler.scheduledAlarmIDs.isEmpty)
    }

    func testModelSchedulesAndCancelsBackupNotificationForCreatedAlarm() async throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
        let backupScheduler = RecordingBackupAlarmScheduler()
        let model = AlarmDashboardModel(
            repository: repository,
            notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
            backupScheduler: backupScheduler,
            runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
        )
        let created = AlarmCardState.make(
            nextFireAt: Date(timeIntervalSince1970: 3_600),
            label: "Created",
            smartEnabled: true,
            snoozeMinutes: 9
        )

        await model.refreshNotificationAuthorization()
        model.create(created)
        await flushMainActorWork()

        XCTAssertEqual(backupScheduler.scheduledAlarmIDs, [created.id])
        XCTAssertTrue(model.exportedLogText.contains("iOSLocalNotification"))
        XCTAssertTrue(model.exportedLogText.contains("authorized"))

        guard let index = model.alarms.firstIndex(where: { $0.id == created.id }) else {
            return XCTFail("expected created alarm to be present")
        }

        model.delete(at: IndexSet(integer: index))

        XCTAssertEqual(backupScheduler.cancelledAlarmIDs, [created.id])
    }

    func testModelSyncsSmartAlarmConfigToWatchAndCancelsOnDelete() async throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
        let connectivity = FakePhoneConnectivityClient()
        let model = AlarmDashboardModel(
            repository: repository,
            notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
            backupScheduler: RecordingBackupAlarmScheduler(),
            connectivity: connectivity,
            runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
        )
        let created = AlarmCardState.make(
            nextFireAt: Date(timeIntervalSince1970: 3_600),
            label: "Watch Sync",
            smartEnabled: true,
            snoozeMinutes: 9
        )

        await model.refreshNotificationAuthorization()
        model.create(created)
        await flushMainActorWork()

        XCTAssertEqual(connectivity.outboundOutbox.count, 1)
        guard let persisted = model.alarms.first(where: { $0.id == created.id }) else {
            return XCTFail("expected created alarm to be present")
        }
        guard case let .alarmConfig(payload) = connectivity.outboundOutbox[0] else {
            return XCTFail("expected first outbound message to be alarm config")
        }
        XCTAssertEqual(payload.alarm.id, created.id)
        XCTAssertEqual(payload.nextFireAt, persisted.nextFireAt)

        guard let index = model.alarms.firstIndex(where: { $0.id == persisted.id }) else {
            return XCTFail("expected persisted alarm to be present")
        }

        model.delete(at: IndexSet(integer: index))

        XCTAssertEqual(connectivity.outboundOutbox.count, 2)
        guard case let .alarmCancelled(alarmId) = connectivity.outboundOutbox[1] else {
            return XCTFail("expected second outbound message to be alarm cancelled")
        }
        XCTAssertEqual(alarmId, created.id)
    }

    func testModelAppliesReturnedWatchArmingStatusToAlarmCard() async throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
        let connectivity = FakePhoneConnectivityClient()
        let model = AlarmDashboardModel(
            repository: repository,
            notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
            backupScheduler: RecordingBackupAlarmScheduler(),
            connectivity: connectivity,
            runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
        )
        let created = AlarmCardState.make(
            nextFireAt: Date.now.addingTimeInterval(3600),
            label: "Round Trip",
            smartEnabled: true,
            snoozeMinutes: 9
        )

        await model.refreshNotificationAuthorization()
        model.create(created)
        await flushMainActorWork()

        connectivity.deliverArmingStatus(WatchArmingStatus(
            alarmId: created.id,
            isArmed: true,
            sessionScheduled: true,
            fallbackChannel: .iOSLocalNotification,
            failureReason: nil
        ))
        await flushMainActorWork()

        guard let updated = model.alarms.first(where: { $0.id == created.id }) else {
            return XCTFail("expected created alarm to be present")
        }
        XCTAssertEqual(updated.smartStatus, .ready)
    }

    func testModelSeedsEmptyRepositoryUsingLocalNotificationFallback() throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())

        let model = AlarmDashboardModel(repository: repository)

        XCTAssertEqual(model.alarms.count, AlarmCardState.seed.count)
        XCTAssertNil(model.userVisibleWarning)
        XCTAssertTrue(model.alarms.allSatisfy { $0.alarm.backupChannelPreferred == .iOSLocalNotification })
        XCTAssertEqual(try repository.list().count, AlarmCardState.seed.count)
    }

    func testModelCreateDeleteAndPreviewUsePersistedLocalNotificationChannel() async throws {
        let repository = AlarmFileRepositoryAdapter(fileURL: temporaryFileURL())
        let model = AlarmDashboardModel(
            repository: repository,
            notificationAuthorizer: FakeNotificationAuthorizer(state: .authorized),
            backupScheduler: RecordingBackupAlarmScheduler(),
            runLogger: AlarmRunLogger(logsDirectory: temporaryDirectoryURL().appendingPathComponent("AlarmRuns", isDirectory: true))
        )
        let created = AlarmCardState.make(
            nextFireAt: Date(timeIntervalSince1970: 3_600),
            label: "Created",
            smartEnabled: true,
            snoozeMinutes: 9
        )

        await model.refreshNotificationAuthorization()
        model.create(created)
        await flushMainActorWork()

        XCTAssertEqual(try repository.alarm(id: created.id)?.backupChannelPreferred, .iOSLocalNotification)

        model.exportPreview()
        XCTAssertTrue(model.exportedLogText.contains("stateTransition"))
        XCTAssertTrue(model.exportedLogText.contains("created_on_phone"))
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

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @MainActor
    private func flushMainActorWork() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }
}

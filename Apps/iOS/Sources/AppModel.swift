import Foundation
import SmartSleepCore
import SwiftUI

@MainActor
final class AlarmDashboardModel: ObservableObject {
    @Published private(set) var alarms: [AlarmCardState] = []
    @Published var notificationAuthorizationState: AuthorizationState = .unknown
    @Published var exportedLogText = ""
    @Published var userVisibleWarning: String?

    private let repository: AlarmRepository
    private let notificationAuthorizer: NotificationAuthorizing
    private let backupScheduler: BackupAlarmScheduling
    private let connectivity: PhoneConnectivityClient
    private let runLogger: AlarmRunLogging
    private let schedulerPolicy = AlarmSchedulerPolicy()
    private var armingStatuses: [UUID: WatchArmingStatus] = [:]
    private var runIDs: [UUID: UUID] = [:]
    private var lastExportedRunID: UUID?

    init(
        repository: AlarmRepository,
        notificationAuthorizer: NotificationAuthorizing = NotificationPermissionService(),
        backupScheduler: BackupAlarmScheduling = BackupAlarmScheduler(),
        connectivity: PhoneConnectivityClient = IOSConnectivityService(),
        runLogger: AlarmRunLogging = AlarmRunLogger.temporary()
    ) {
        self.repository = repository
        self.notificationAuthorizer = notificationAuthorizer
        self.backupScheduler = backupScheduler
        self.connectivity = connectivity
        self.runLogger = runLogger
        self.connectivity.onArmingStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.applyArmingStatus(status)
            }
        }
        reload()
        Task { await refreshNotificationAuthorization() }
        applyArmingStatus(connectivity.lastArmingStatus)
    }

    convenience init() {
        do {
            try self.init(
                repository: AlarmFileRepositoryAdapter.appStorage(),
                runLogger: AlarmRunLogger.appStorage()
            )
        } catch {
            self.init(
                repository: MemoryAlarmRepository(),
                runLogger: AlarmRunLogger.temporary()
            )
            self.userVisibleWarning = "Alarm storage unavailable; using temporary alarms."
        }
    }

    func reload() {
        do {
            let persisted = try repository.list()
            alarms = persisted.map { alarm in
                AlarmCardState.from(alarm: alarm, armingStatus: armingStatuses[alarm.id])
            }
            if alarms.isEmpty {
                alarms = AlarmCardState.seed
                for item in alarms {
                    try repository.save(item.alarm)
                    if let armingStatus = item.armingStatus {
                        armingStatuses[item.id] = armingStatus
                    }
                }
            }
            userVisibleWarning = nil
        } catch {
            userVisibleWarning = "Failed to load alarms."
        }
    }

    func create(_ alarm: AlarmCardState) {
        do {
            try repository.save(alarm.alarm)
            let runId = UUID()
            runIDs[alarm.id] = runId
            lastExportedRunID = runId
            try runLogger.recordAlarmCreated(runId: runId)
            reload()
            if let persisted = alarms.first(where: { $0.id == alarm.id }) {
                scheduleFallbackIfNeeded(for: persisted, runId: runId)
                if persisted.alarm.smartEnabled {
                    connectivity.sendAlarmConfig(AlarmConfigPayload(
                        alarm: persisted.alarm,
                        nextFireAt: persisted.nextFireAt
                    ))
                }
            }
        } catch {
            userVisibleWarning = "Failed to save alarm."
            exportedLogText = #"{"error":"failed_to_save_alarm"}"#
        }
    }

    func delete(at offsets: IndexSet) {
        let ids = offsets.map { alarms[$0].id }
        do {
            for id in ids {
                try repository.delete(id: id)
                backupScheduler.cancelBackup(for: id)
                connectivity.cancelAlarm(id: id)
            }
            reload()
        } catch {
            userVisibleWarning = "Failed to delete alarm."
            exportedLogText = #"{"error":"failed_to_delete_alarm"}"#
        }
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

    func exportPreview() {
        if let lastExportedRunID, let exported = try? runLogger.export(runId: lastExportedRunID), !exported.isEmpty {
            exportedLogText = exported
            return
        }
        exportedLogText = LogPreviewBuilder.makePreview(for: alarms)
    }

    private func scheduleFallbackIfNeeded(for item: AlarmCardState, runId: UUID) {
        let decision = schedulerPolicy.decision(for: item.alarm, arming: item.armingStatus)
        guard decision.shouldSchedulePhoneBackup else { return }

        Task { @MainActor in
            let authorizationState = await authorizationStateForScheduling()
            do {
                let log = try await backupScheduler.scheduleBackup(
                    for: item.alarm,
                    nextFireAt: item.nextFireAt,
                    runId: runId,
                    authorizationState: authorizationState
                )
                try runLogger.recordChannelLog(log)
                exportedLogText = (try? runLogger.export(runId: runId)) ?? encodedFallback(log)
                updateFallbackWarning(for: log)
            } catch {
                let failedLog = AlarmChannelLog(
                    runId: runId,
                    channel: .iOSLocalNotification,
                    scheduledAt: Date(),
                    firedAt: nil,
                    stoppedAt: nil,
                    snoozedAt: nil,
                    cancelledAt: nil,
                    authorizationState: authorizationState,
                    failureReason: "notification_schedule_failed",
                    userVisibleState: "schedule_failed"
                )
                try? runLogger.recordChannelLog(failedLog)
                exportedLogText = (try? runLogger.export(runId: runId)) ?? encodedFallback(failedLog)
                userVisibleWarning = "Failed to schedule fallback notification."
            }
        }
    }

    private func applyArmingStatus(_ status: WatchArmingStatus?) {
        guard let status else { return }
        armingStatuses[status.alarmId] = status

        guard let index = alarms.firstIndex(where: { $0.id == status.alarmId }) else { return }
        alarms[index].armingStatus = status
    }

    private func authorizationStateForScheduling() async -> AuthorizationState {
        if notificationAuthorizationState == .unknown {
            notificationAuthorizationState = await notificationAuthorizer.authorizationState()
        }

        if notificationAuthorizationState == .notDetermined {
            do {
                notificationAuthorizationState = try await notificationAuthorizer.requestAuthorization()
            } catch {
                notificationAuthorizationState = .denied
            }
        }

        return notificationAuthorizationState
    }

    private func updateFallbackWarning(for log: AlarmChannelLog) {
        if log.failureReason == "notification_not_authorized" {
            userVisibleWarning = "iPhone fallback notifications are not authorized."
        } else {
            userVisibleWarning = nil
        }
    }

    private func encodedFallback(_ log: AlarmChannelLog) -> String {
        guard let data = try? JSONEncoder().encode(log),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }
}

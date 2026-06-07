import Foundation
import SmartSleepCore
import UserNotifications

protocol BackupAlarmScheduling {
    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState
    ) async throws -> AlarmChannelLog
    func cancelBackup(for alarmId: UUID)
}

final class RecordingBackupAlarmScheduler: BackupAlarmScheduling {
    private(set) var scheduledAlarmIDs: [UUID] = []
    private(set) var cancelledAlarmIDs: [UUID] = []

    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState
    ) async throws -> AlarmChannelLog {
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
                userVisibleState: "not_authorized"
            )
        }
        scheduledAlarmIDs.append(alarm.id)
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
        cancelledAlarmIDs.append(alarmId)
    }
}

struct BackupAlarmScheduler: BackupAlarmScheduling {
    func scheduleBackup(
        for alarm: Alarm,
        nextFireAt: Date,
        runId: UUID,
        authorizationState: AuthorizationState
    ) async throws -> AlarmChannelLog {
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
                userVisibleState: "not_authorized"
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
            userVisibleState: "scheduled"
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

private extension Weekday {
    var calendarWeekday: Int {
        switch self {
        case .sunday:
            return 1
        case .monday:
            return 2
        case .tuesday:
            return 3
        case .wednesday:
            return 4
        case .thursday:
            return 5
        case .friday:
            return 6
        case .saturday:
            return 7
        }
    }
}

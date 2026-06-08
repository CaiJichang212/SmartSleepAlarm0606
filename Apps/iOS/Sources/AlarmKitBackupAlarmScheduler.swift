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

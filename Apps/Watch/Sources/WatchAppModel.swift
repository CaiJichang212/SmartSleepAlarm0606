import Foundation
import SmartSleepCore
import SwiftUI

@MainActor
final class WatchAppModel: ObservableObject {
    @Published var currentState: SmartAlarmState = .needsWatchArming
    @Published var sessionScheduled = false
    @Published var lastConfig: AlarmConfigPayload?
    @Published var failureReason: String?

    private let connectivity: WatchConnectivityClient
    private let runtimeScheduler: RuntimeSessionScheduling
    private let ringer: WatchAlarmRinging
    private var activeAlarmID: UUID?
    private var activeRunID: UUID?

    init(
        connectivity: WatchConnectivityClient = WatchConnectivityService(),
        runtimeScheduler: RuntimeSessionScheduling = WatchRuntimeSessionScheduler(),
        ringer: WatchAlarmRinging = WatchAlarmRinger()
    ) {
        self.connectivity = connectivity
        self.runtimeScheduler = runtimeScheduler
        self.ringer = ringer
        self.lastConfig = connectivity.latestAlarmConfig
        self.runtimeScheduler.onLogUpdated = { [weak self] log in
            self?.handleRuntimeLogUpdate(log)
        }
        self.connectivity.onConfigChanged = { [weak self] config in
            self?.handleConfigChange(config)
        }
    }

    func armCurrentAlarm() {
        guard let config = lastConfig else {
            sessionScheduled = false
            currentState = .fallbackPhoneAlarm
            failureReason = "missing_alarm_config"
            activeAlarmID = nil
            activeRunID = nil
            let alarmId = UUID()
            let status = WatchArmingStatus(
                alarmId: alarmId,
                isArmed: false,
                sessionScheduled: false,
                fallbackChannel: .iOSLocalNotification,
                failureReason: "missing_alarm_config"
            )
            connectivity.sendArmingResult(ArmingResultPayload(alarmId: alarmId, armedAt: Date(), status: status))
            return
        }

        let runId = UUID()
        activeAlarmID = config.alarm.id
        activeRunID = runId
        let runtimeLog = runtimeScheduler.schedule(for: config, runId: runId)
        sessionScheduled = runtimeLog.errorCode == nil
        currentState = sessionScheduled ? .sessionScheduled : .fallbackPhoneAlarm
        failureReason = sessionScheduled ? nil : "runtime_session_not_scheduled"

        let status = WatchArmingStatus(
            alarmId: config.alarm.id,
            isArmed: sessionScheduled,
            sessionScheduled: sessionScheduled,
            fallbackChannel: .iOSLocalNotification,
            failureReason: failureReason
        )
        connectivity.sendArmingResult(ArmingResultPayload(
            alarmId: config.alarm.id,
            armedAt: Date(),
            status: status
        ))
        connectivity.sendSessionResult(SessionResultPayload(
            alarmId: config.alarm.id,
            runId: runId,
            state: currentState,
            scheduledAt: runtimeLog.scheduledAt,
            failureReason: failureReason
        ))
    }

    func simulateRinging() {
        currentState = .ringing
        ringer.startRinging()
    }

    func snooze() {
        currentState = .snoozed
        ringer.snooze()
    }

    func stop() {
        currentState = .completed
        ringer.stop()
    }

    private func handleConfigChange(_ config: AlarmConfigPayload?) {
        lastConfig = config

        guard config == nil else {
            failureReason = nil
            return
        }

        activeAlarmID = nil
        activeRunID = nil
        runtimeScheduler.invalidate()
        sessionScheduled = false
        currentState = .needsWatchArming
        failureReason = "missing_alarm_config"
    }

    private func handleRuntimeLogUpdate(_ log: RuntimeSessionLog) {
        guard let activeAlarmID, let activeRunID, activeRunID == log.runId else { return }
        guard log.errorCode != nil || log.invalidatedAt != nil else { return }

        sessionScheduled = false
        currentState = .fallbackPhoneAlarm
        failureReason = log.errorCode ?? log.invalidationReason ?? "runtime_session_invalidated"

        let status = WatchArmingStatus(
            alarmId: activeAlarmID,
            isArmed: false,
            sessionScheduled: false,
            fallbackChannel: .iOSLocalNotification,
            failureReason: failureReason
        )
        connectivity.sendArmingResult(ArmingResultPayload(
            alarmId: activeAlarmID,
            armedAt: Date(),
            status: status
        ))
        connectivity.sendSessionResult(SessionResultPayload(
            alarmId: activeAlarmID,
            runId: activeRunID,
            state: currentState,
            scheduledAt: log.scheduledAt,
            failureReason: failureReason
        ))
    }
}

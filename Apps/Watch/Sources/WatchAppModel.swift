import Foundation
import SmartSleepCore
import SwiftUI

struct WatchAlarmRunEngineFactory {
    var featureFlags: FeatureFlags

    init(featureFlags: FeatureFlags = .v02Default) {
        self.featureFlags = featureFlags
    }

    @MainActor
    func make(initialState: SmartAlarmState, ringer: WatchAlarmRinging) -> WatchAlarmRunEngine {
        WatchAlarmRunEngine(
            initialState: initialState,
            ringer: ringer,
            featureFlags: featureFlags
        )
    }
}

@MainActor
final class WatchAppModel: ObservableObject {
    private static let maxFreshnessLagSec: TimeInterval = 5

    @Published var currentState: SmartAlarmState = .needsWatchArming
    @Published var sessionScheduled = false
    @Published var lastConfig: AlarmConfigPayload?
    @Published var failureReason: String?

    private let connectivity: WatchConnectivityClient
    private let runtimeScheduler: RuntimeSessionScheduling
    private let ringer: WatchAlarmRinging
    private let runLogger: WatchAlarmRunLogging
    private let sensorSampler: WatchSensorSampling
    private let preflightChecker: WatchPreflightChecking
    private let engineFactory: WatchAlarmRunEngineFactory
    private var runEngine: WatchAlarmRunEngine?
    private var ringTask: Task<Void, Never>?
    private var activeAlarmID: UUID?
    private var activeRunID: UUID?
    private var latestFreshness: SensorFreshness?
    private var ignoredRuntimeUpdateRunIDs: Set<UUID> = []

    init(
        connectivity: WatchConnectivityClient = WatchConnectivityService(),
        runtimeScheduler: RuntimeSessionScheduling = WatchRuntimeSessionScheduler(),
        ringer: WatchAlarmRinging = WatchAlarmRinger(),
        runLogger: WatchAlarmRunLogging = WatchAlarmRunLogger.temporary(),
        sensorSampler: WatchSensorSampling = CoreMotionWatchSensorSampler(),
        preflightChecker: WatchPreflightChecking = WatchPreflightChecker(),
        engineFactory: WatchAlarmRunEngineFactory = WatchAlarmRunEngineFactory()
    ) {
        self.connectivity = connectivity
        self.runtimeScheduler = runtimeScheduler
        self.ringer = ringer
        self.runLogger = runLogger
        self.sensorSampler = sensorSampler
        self.preflightChecker = preflightChecker
        self.engineFactory = engineFactory
        self.lastConfig = connectivity.latestAlarmConfig
        self.runtimeScheduler.onLogUpdated = { [weak self] log in
            self?.handleRuntimeLogUpdate(log)
        }
        self.runtimeScheduler.onRuntimeStarted = { [weak self] log in
            Task { @MainActor in
                guard let self, let config = self.lastConfig else { return }
                self.runEngine?.runtimeDidStart(log, nextFireAt: config.nextFireAt, runLogger: self.runLogger)
                if let state = self.runEngine?.state {
                    self.currentState = state
                }
                if let activeRunID = self.activeRunID {
                    self.sensorSampler.start(runId: activeRunID)
                }
                let seconds = max(0, config.nextFireAt.timeIntervalSince(Date()))
                self.ringTask?.cancel()
                self.ringTask = Task { [weak self] in
                    let nanoseconds = UInt64(seconds * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    await MainActor.run {
                        guard let self else { return }
                        self.runEngine?.ringTimeReached(runLogger: self.runLogger)
                        if let state = self.runEngine?.state {
                            self.currentState = state
                        }
                    }
                }
            }
        }
        self.sensorSampler.onFreshness = { [weak self] freshness in
            Task { @MainActor in
                guard let self else { return }
                try? self.runLogger.recordFreshness(freshness)
                self.latestFreshness = freshness
                let smartActiveStates: Set<SmartAlarmState> = [.preMonitoring, .ringing, .awakeCandidate, .reRinging]
                if !freshness.motionFresh && smartActiveStates.contains(self.currentState) {
                    if let runEngine = self.runEngine {
                        runEngine.motionBecameStale(runLogger: self.runLogger, at: freshness.timestamp)
                        self.currentState = runEngine.state
                    } else {
                        self.transitionState(to: .ringingNoSmart, reason: "motion_became_stale", at: freshness.timestamp)
                    }
                }
            }
        }
        self.sensorSampler.onSummary = { [weak self] summary in
            Task { @MainActor in
                guard let self else { return }
                try? self.runLogger.recordSummary(summary)
                guard let freshness = self.latestFreshness,
                      freshness.runId == summary.runId,
                      self.isFreshnessUsableForSummary(freshness, summary: summary),
                      let runEngine = self.runEngine else { return }
                if [.ringing, .reRinging, .awakeCandidate].contains(self.currentState) {
                    _ = runEngine.evaluateAwake(
                        summary: summary,
                        freshness: freshness,
                        now: summary.windowEnd,
                        runLogger: self.runLogger
                    )
                    self.currentState = runEngine.state
                } else if self.currentState == .silencedMonitoring {
                    _ = runEngine.evaluateReSleep(
                        summary: summary,
                        freshness: freshness,
                        now: summary.windowEnd,
                        runLogger: self.runLogger
                    )
                    self.currentState = runEngine.state
                }
            }
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

        let preflight = preflightChecker.check(nextFireAt: config.nextFireAt, now: Date())
        guard preflight.canArmSmartMode else {
            sessionScheduled = false
            failureReason = preflight.failureReason ?? "watch_preflight_failed"
            transitionState(
                to: .fallbackPhoneAlarm,
                reason: failureReason ?? "watch_preflight_failed",
                featureSnapshotId: preflightSnapshot(for: preflight, nextFireAt: config.nextFireAt),
                errorCode: failureReason
            )
            let status = WatchArmingStatus(
                alarmId: config.alarm.id,
                isArmed: false,
                sessionScheduled: false,
                fallbackChannel: .iOSLocalNotification,
                failureReason: failureReason
            )
            connectivity.sendArmingResult(ArmingResultPayload(alarmId: config.alarm.id, armedAt: Date(), status: status))
            connectivity.sendSessionResult(SessionResultPayload(
                alarmId: config.alarm.id,
                runId: runId,
                state: currentState,
                scheduledAt: nil,
                failureReason: failureReason
            ))
            sendRunSummary(outcome: nil, fallbackUsed: true)
            return
        }

        let runtimeLog = runtimeScheduler.schedule(for: config, runId: runId)
        try? runLogger.recordRuntimeSession(runtimeLog)
        sessionScheduled = runtimeLog.errorCode == nil
        transitionState(
            to: sessionScheduled ? .sessionScheduled : .fallbackPhoneAlarm,
            reason: sessionScheduled ? "runtime_session_scheduled" : "runtime_session_failed",
            errorCode: runtimeLog.errorCode
        )
        failureReason = sessionScheduled ? nil : "runtime_session_not_scheduled"
        if sessionScheduled {
            runEngine = engineFactory.make(initialState: .sessionScheduled, ringer: ringer)
        }

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
        if let runEngine {
            runEngine.ringTimeReached(runLogger: runLogger)
            currentState = runEngine.state
        } else {
            currentState = .ringing
            ringer.startRinging()
        }
    }

    func snooze() {
        ringTask?.cancel()
        ringTask = nil
        sensorSampler.stop()
        if let runEngine {
            runEngine.snooze(runLogger: runLogger)
            currentState = runEngine.state
            sendRunSummary(outcome: .userSnoozed)
        } else {
            transitionState(to: .snoozed, reason: "user_snoozed")
            ringer.snooze()
        }
    }

    func stop() {
        ringTask?.cancel()
        ringTask = nil
        sensorSampler.stop()
        if let runEngine {
            runEngine.stop(runLogger: runLogger)
            currentState = runEngine.state
            sendRunSummary(outcome: .userStopped)
        } else {
            transitionState(to: .completed, reason: "user_stopped")
            ringer.stop()
        }
    }

    private func handleConfigChange(_ config: AlarmConfigPayload?) {
        lastConfig = config

        guard config == nil else {
            failureReason = nil
            return
        }

        if let activeRunID {
            ignoredRuntimeUpdateRunIDs.insert(activeRunID)
        }
        ringTask?.cancel()
        ringTask = nil
        sensorSampler.stop()
        runtimeScheduler.invalidate()
        sessionScheduled = false
        transitionState(to: .needsWatchArming, reason: "alarm_config_removed")
        sendRunSummary(outcome: nil, fallbackUsed: false)
        failureReason = "missing_alarm_config"
        activeAlarmID = nil
        activeRunID = nil
        latestFreshness = nil
        runEngine = nil
    }

    private func handleRuntimeLogUpdate(_ log: RuntimeSessionLog) {
        if ignoredRuntimeUpdateRunIDs.remove(log.runId) != nil {
            return
        }
        try? runLogger.recordRuntimeSession(log)
        guard let activeAlarmID, let activeRunID, activeRunID == log.runId else { return }
        let isRuntimeInvalidation = log.invalidatedAt != nil
        let isPostStartError = log.errorCode != nil && log.actualStartAt != nil
        guard isRuntimeInvalidation || isPostStartError else { return }

        sensorSampler.stop()
        sessionScheduled = false
        transitionState(
            to: .fallbackPhoneAlarm,
            reason: "runtime_session_invalidated",
            at: log.invalidatedAt ?? Date(),
            errorCode: log.errorCode ?? log.invalidationReason
        )
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
        sendRunSummary(outcome: nil, fallbackUsed: true)
    }

    private func sendRunSummary(outcome: OutcomeKind?, fallbackUsed: Bool = false) {
        guard let activeRunID else { return }
        let count = (try? runLogger.eventCount(runId: activeRunID)) ?? 0
        connectivity.sendRunLogSummary(RunLogSummaryPayload(
            runId: activeRunID,
            finalState: currentState,
            outcome: outcome,
            eventCount: count,
            fallbackUsed: fallbackUsed
        ))
    }

    private func transitionState(
        to newState: SmartAlarmState,
        reason: String,
        at date: Date = Date(),
        featureSnapshotId: String? = nil,
        errorCode: String? = nil
    ) {
        let previousState = currentState
        currentState = newState
        guard let activeRunID, previousState != newState else { return }
        try? runLogger.recordStateTransition(StateTransitionLog(
            runId: activeRunID,
            fromState: previousState,
            toState: newState,
            timestamp: date,
            reason: reason,
            confidence: nil,
            featureSnapshotId: featureSnapshotId,
            errorCode: errorCode
        ))
    }

    private func isFreshnessUsableForSummary(_ freshness: SensorFreshness, summary: SensorSummary) -> Bool {
        guard freshness.timestamp <= summary.windowEnd else { return false }
        return summary.windowEnd.timeIntervalSince(freshness.timestamp) <= Self.maxFreshnessLagSec
    }

    private func preflightSnapshot(for result: WatchPreflightResult, nextFireAt: Date, checkedAt: Date = Date()) -> String {
        let batteryText = result.batteryLevel.map { String(format: "%.2f", $0) } ?? "nil"
        return [
            "preflightFailure",
            "reason=\(result.failureReason ?? "watch_preflight_failed")",
            "batteryLevel=\(batteryText)",
            "motionAvailable=\(result.motionAvailable)",
            "nextFireAt=\(nextFireAt.timeIntervalSince1970)",
            "checkedAt=\(checkedAt.timeIntervalSince1970)"
        ].joined(separator: ";")
    }
}

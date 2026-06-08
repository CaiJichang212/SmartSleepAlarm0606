import Foundation
import SmartSleepCore

@MainActor
final class WatchAlarmRunEngine: ObservableObject {
    @Published private(set) var state: SmartAlarmState
    private let ringer: WatchAlarmRinging
    private let featureFlags: FeatureFlags
    private let reSleepScorer: ReSleepRiskScorer
    private var reAlarmCount = 0
    private var silencedAt: Date?

    init(
        initialState: SmartAlarmState = .sessionScheduled,
        ringer: WatchAlarmRinging,
        featureFlags: FeatureFlags = .v02Default,
        reSleepScorer: ReSleepRiskScorer = ReSleepRiskScorer()
    ) {
        self.state = initialState
        self.ringer = ringer
        self.featureFlags = featureFlags
        self.reSleepScorer = reSleepScorer
    }

    private var activeRunId: UUID?

    func runtimeDidStart(
        _ log: RuntimeSessionLog,
        nextFireAt: Date,
        runLogger: WatchAlarmRunLogging
    ) {
        guard log.errorCode == nil, log.invalidatedAt == nil else {
            state = .fallbackPhoneAlarm
            return
        }
        activeRunId = log.runId
        transition(to: .preMonitoring, reason: "runtime_started", at: log.actualStartAt ?? Date(), runLogger: runLogger)
    }

    func ringTimeReached(runLogger: WatchAlarmRunLogging, at date: Date = Date()) {
        guard state == .preMonitoring || state == .sessionScheduled || state == .ringingNoSmart else { return }
        if state == .preMonitoring || state == .sessionScheduled {
            transition(to: .ringing, reason: "ring_time_reached", at: date, runLogger: runLogger)
        }
        ringer.startRinging()
        guard let activeRunId else { return }
        try? runLogger.recordChannel(AlarmChannelLog(
            runId: activeRunId,
            channel: .watchRuntimeHapticAudio,
            scheduledAt: date,
            firedAt: date,
            stoppedAt: nil,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: state == .ringingNoSmart ? "ringing_no_smart" : "ringing"
        ))
    }

    func snooze(runLogger: WatchAlarmRunLogging, at date: Date = Date()) {
        guard state == .ringing || state == .reRinging || state == .ringingNoSmart else { return }
        transition(to: .snoozed, reason: "user_snoozed", at: date, runLogger: runLogger)
        ringer.snooze()
        guard let activeRunId else { return }
        try? runLogger.recordChannel(AlarmChannelLog(
            runId: activeRunId,
            channel: .watchRuntimeHapticAudio,
            scheduledAt: date,
            firedAt: nil,
            stoppedAt: nil,
            snoozedAt: date,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: "snoozed"
        ))
    }

    func stop(runLogger: WatchAlarmRunLogging, at date: Date = Date()) {
        guard state == .ringing || state == .reRinging || state == .snoozed || state == .ringingNoSmart else { return }
        transition(to: .completed, reason: "user_stopped", at: date, runLogger: runLogger)
        ringer.stop()
        guard let activeRunId else { return }
        try? runLogger.recordChannel(AlarmChannelLog(
            runId: activeRunId,
            channel: .watchRuntimeHapticAudio,
            scheduledAt: date,
            firedAt: nil,
            stoppedAt: date,
            snoozedAt: nil,
            cancelledAt: nil,
            authorizationState: .authorized,
            failureReason: nil,
            userVisibleState: "stopped"
        ))
        try? runLogger.recordOutcome(OutcomeLabel(
            runId: activeRunId,
            manualStop: true,
            manualSnooze: false,
            gestureSnooze: false,
            autoSilenceAccepted: false,
            falseSilenceReported: false,
            falseReAlarmReported: false,
            missedAlarmReported: false,
            fallbackUsed: false,
            userReportedStillAsleep: false,
            userReportedAwake: false,
            notes: nil,
            labeledAt: date
        ))
    }

    func motionBecameStale(runLogger: WatchAlarmRunLogging, at date: Date = Date()) {
        let activeStates: Set<SmartAlarmState> = [.preMonitoring, .ringing, .awakeCandidate, .reRinging]
        guard activeStates.contains(state) else { return }
        transition(to: .ringingNoSmart, reason: "motion_became_stale", at: date, runLogger: runLogger)
    }

    func autoSilenceConfirmed(at date: Date = Date()) {
        guard featureFlags.autoSilenceEnabled else { return }
        state = .silencedMonitoring
        silencedAt = date
    }

    func evaluateReSleep(summary: SensorSummary, freshness: SensorFreshness, now: Date = Date()) -> ReSleepRiskResult? {
        guard featureFlags.reSleepDetectionEnabled, state == .silencedMonitoring, let silencedAt else { return nil }
        let result = reSleepScorer.evaluate(
            monitoringElapsedSec: now.timeIntervalSince(silencedAt),
            summary: summary,
            freshness: freshness,
            reAlarmCount: reAlarmCount,
            maxReAlarmCount: featureFlags.maxReAlarmCount
        )
        if result.shouldReRing {
            reAlarmCount += 1
            transition(to: .reRinging, reason: "re_ring_requested", at: now, runLogger: nil)
            ringer.startRinging()
        }
        return result
    }

    private func transition(
        to newState: SmartAlarmState,
        reason: String,
        at date: Date,
        runLogger: WatchAlarmRunLogging?
    ) {
        let previousState = state
        state = newState
        guard let activeRunId, previousState != newState else { return }
        try? runLogger?.recordStateTransition(StateTransitionLog(
            runId: activeRunId,
            fromState: previousState,
            toState: newState,
            timestamp: date,
            reason: reason,
            confidence: nil,
            featureSnapshotId: nil,
            errorCode: nil
        ))
    }
}

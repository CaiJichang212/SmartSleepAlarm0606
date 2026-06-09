import Foundation
import SmartSleepCore
@testable import SmartSleepWatch

final class FakeWatchConnectivityClient: WatchConnectivityClient {
    var latestAlarmConfig: AlarmConfigPayload? {
        didSet { onConfigChanged?(latestAlarmConfig) }
    }
    var onConfigChanged: ((AlarmConfigPayload?) -> Void)?
    private(set) var outboundMessages: [SmartSleepConnectivityMessage] = []

    init(latestAlarmConfig: AlarmConfigPayload? = nil) {
        self.latestAlarmConfig = latestAlarmConfig
    }

    func sendArmingResult(_ payload: ArmingResultPayload) {
        outboundMessages.append(.armingResult(payload))
    }

    func sendSessionResult(_ payload: SessionResultPayload) {
        outboundMessages.append(.sessionResult(payload))
    }

    func sendRunLogSummary(_ payload: RunLogSummaryPayload) {
        outboundMessages.append(.runLogSummary(payload))
    }

    func deliverCancellation(for alarmId: UUID) {
        if latestAlarmConfig?.alarm.id == alarmId {
            latestAlarmConfig = nil
        }
    }
}

final class FakeRuntimeSessionScheduler: RuntimeSessionScheduling {
    var shouldSucceed: Bool
    var latestLog: RuntimeSessionLog? {
        didSet {
            if let latestLog {
                onLogUpdated?(latestLog)
            }
        }
    }
    var onLogUpdated: ((RuntimeSessionLog) -> Void)?
    var onRuntimeStarted: ((RuntimeSessionLog) -> Void)?
    private(set) var invalidateCallCount = 0
    private(set) var lastRunID: UUID?

    init(shouldSucceed: Bool) {
        self.shouldSucceed = shouldSucceed
    }

    func schedule(for payload: AlarmConfigPayload, runId: UUID) -> RuntimeSessionLog {
        lastRunID = runId
        let log = RuntimeSessionLog(
            runId: runId,
            sessionType: "fakeSmartAlarmPreMonitoring",
            scheduledAt: Date(),
            targetStartAt: payload.nextFireAt.addingTimeInterval(-30 * 60),
            actualStartAt: nil,
            invalidatedAt: nil,
            invalidationReason: nil,
            startLatencySec: nil,
            didStartBeforeAlarm: false,
            didReachRingTime: false,
            errorCode: shouldSucceed ? nil : "fake_runtime_schedule_failed",
            errorMessage: shouldSucceed ? nil : "Fake runtime scheduler was configured to fail."
        )
        latestLog = log
        return log
    }

    func invalidate() {
        invalidateCallCount += 1
    }

    func emitInvalidation(_ log: RuntimeSessionLog) {
        latestLog = log
    }

    func emitStart(_ log: RuntimeSessionLog) {
        latestLog = log
        onRuntimeStarted?(log)
    }
}

final class FakeWatchAlarmRinger: WatchAlarmRinging {
    private(set) var startCallCount = 0
    private(set) var snoozeCallCount = 0
    private(set) var stopCallCount = 0

    func startRinging() {
        startCallCount += 1
    }

    func snooze() {
        snoozeCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

final class FakeWatchAlarmRunLogger: WatchAlarmRunLogging {
    private(set) var stateTransitionLogs: [StateTransitionLog] = []
    private(set) var runtimeLogs: [RuntimeSessionLog] = []
    private(set) var channelLogs: [AlarmChannelLog] = []
    private(set) var freshnessLogs: [SensorFreshness] = []
    private(set) var summaryLogs: [SensorSummary] = []
    private(set) var gestureLogs: [GestureEvent] = []
    private(set) var outcomeLogs: [OutcomeLabel] = []

    func recordStateTransition(_ log: StateTransitionLog) throws { stateTransitionLogs.append(log) }
    func recordRuntimeSession(_ log: RuntimeSessionLog) throws { runtimeLogs.append(log) }
    func recordChannel(_ log: AlarmChannelLog) throws { channelLogs.append(log) }
    func recordFreshness(_ freshness: SensorFreshness) throws { freshnessLogs.append(freshness) }
    func recordSummary(_ summary: SensorSummary) throws { summaryLogs.append(summary) }
    func recordGesture(_ gesture: GestureEvent) throws { gestureLogs.append(gesture) }
    func recordOutcome(_ outcome: OutcomeLabel) throws { outcomeLogs.append(outcome) }

    func eventCount(runId: UUID) throws -> Int {
        let stateCount = stateTransitionLogs.filter { $0.runId == runId }.count
        let runtimeCount = runtimeLogs.filter { $0.runId == runId }.count
        let channelCount = channelLogs.filter { $0.runId == runId }.count
        let freshnessCount = freshnessLogs.filter { $0.runId == runId }.count
        let summaryCount = summaryLogs.filter { $0.runId == runId }.count
        let gestureCount = gestureLogs.filter { $0.runId == runId }.count
        let outcomeCount = outcomeLogs.filter { $0.runId == runId }.count
        return stateCount + runtimeCount + channelCount + freshnessCount + summaryCount + gestureCount + outcomeCount
    }

    func export(runId: UUID) throws -> String { "" }
}

final class FakeWatchSensorSampler: WatchSensorSampling {
    var onFreshness: ((SensorFreshness) -> Void)?
    var onSummary: ((SensorSummary) -> Void)?
    private(set) var activeRunId: UUID?

    func start(runId: UUID) {
        activeRunId = runId
    }

    func stop() {
        activeRunId = nil
    }

    func emitFreshness(_ freshness: SensorFreshness) {
        onFreshness?(freshness)
    }

    func emitSummary(_ summary: SensorSummary) {
        onSummary?(summary)
    }
}

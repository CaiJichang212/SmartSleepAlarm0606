import Foundation
import SmartSleepCore

protocol WatchAlarmRunLogging {
    func recordStateTransition(_ log: StateTransitionLog) throws
    func recordRuntimeSession(_ log: RuntimeSessionLog) throws
    func recordChannel(_ log: AlarmChannelLog) throws
    func recordFreshness(_ freshness: SensorFreshness) throws
    func recordGesture(_ gesture: GestureEvent) throws
    func recordOutcome(_ outcome: OutcomeLabel) throws
    func export(runId: UUID) throws -> String
}

struct WatchAlarmRunLogger: WatchAlarmRunLogging {
    let logsDirectory: URL

    init(logsDirectory: URL) throws {
        self.logsDirectory = logsDirectory
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    func recordStateTransition(_ log: StateTransitionLog) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.stateTransition(log), recordedAt: log.timestamp)
    }

    func recordRuntimeSession(_ log: RuntimeSessionLog) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.runtimeSession(log), recordedAt: log.actualStartAt ?? log.scheduledAt)
    }

    func recordChannel(_ log: AlarmChannelLog) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.channel(log), recordedAt: log.firedAt ?? log.scheduledAt)
    }

    func recordFreshness(_ freshness: SensorFreshness) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.sensorFreshness(freshness), recordedAt: freshness.timestamp)
    }

    func recordGesture(_ gesture: GestureEvent) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.gesture(gesture), recordedAt: gesture.timestamp)
    }

    func recordOutcome(_ outcome: OutcomeLabel) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.outcome(outcome), recordedAt: outcome.labeledAt)
    }

    func export(runId: UUID) throws -> String {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        return try store.export(runId: runId).joined(separator: "\n")
    }

    static func appStorage() throws -> WatchAlarmRunLogger {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try WatchAlarmRunLogger(logsDirectory: documents.appendingPathComponent("AlarmRuns", isDirectory: true))
    }

    static func temporary() -> WatchAlarmRunLogger {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("AlarmRuns", isDirectory: true)
        return try! WatchAlarmRunLogger(logsDirectory: directory)
    }
}

final class FakeWatchAlarmRunLogger: WatchAlarmRunLogging {
    private(set) var stateTransitionLogs: [StateTransitionLog] = []
    private(set) var runtimeLogs: [RuntimeSessionLog] = []
    private(set) var channelLogs: [AlarmChannelLog] = []
    private(set) var freshnessLogs: [SensorFreshness] = []
    private(set) var gestureLogs: [GestureEvent] = []
    private(set) var outcomeLogs: [OutcomeLabel] = []

    func recordStateTransition(_ log: StateTransitionLog) throws { stateTransitionLogs.append(log) }
    func recordRuntimeSession(_ log: RuntimeSessionLog) throws { runtimeLogs.append(log) }
    func recordChannel(_ log: AlarmChannelLog) throws { channelLogs.append(log) }
    func recordFreshness(_ freshness: SensorFreshness) throws { freshnessLogs.append(freshness) }
    func recordGesture(_ gesture: GestureEvent) throws { gestureLogs.append(gesture) }
    func recordOutcome(_ outcome: OutcomeLabel) throws { outcomeLogs.append(outcome) }
    func export(runId: UUID) throws -> String { "" }
}

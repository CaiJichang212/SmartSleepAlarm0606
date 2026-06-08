import Foundation
import SmartSleepCore

protocol AlarmRunLogging {
    func recordAlarmCreated(runId: UUID) throws
    func recordChannelLog(_ log: AlarmChannelLog) throws
    func recordOutcome(_ outcome: OutcomeLabel) throws
    func export(runId: UUID) throws -> String
}

struct AlarmRunLogger: AlarmRunLogging {
    let logsDirectory: URL

    func recordAlarmCreated(runId: UUID) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        var coordinator = AlarmRunCoordinator(runId: runId, eventStore: store)
        try coordinator.apply(.phoneCreatedAlarm, reason: "created_on_phone")
    }

    func recordChannelLog(_ log: AlarmChannelLog) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.channel(log))
    }

    func recordOutcome(_ outcome: OutcomeLabel) throws {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        try store.append(.outcome(outcome), recordedAt: outcome.labeledAt)
    }

    func export(runId: UUID) throws -> String {
        try LogExportService(logsDirectory: logsDirectory).export(runId: runId)
    }

    static func appStorage() throws -> AlarmRunLogger {
        let service = try LogExportService.appStorage()
        return AlarmRunLogger(logsDirectory: service.logsDirectory)
    }

    static func temporary() -> AlarmRunLogger {
        AlarmRunLogger(
            logsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("AlarmRuns", isDirectory: true)
        )
    }
}

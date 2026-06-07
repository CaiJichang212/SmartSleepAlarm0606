import Foundation
import SmartSleepCore

protocol AlarmRunExporting {
    func export(runId: UUID) throws -> String
}

struct LogExportService: AlarmRunExporting {
    private let logsDirectory: URL

    init(logsDirectory: URL) {
        self.logsDirectory = logsDirectory
    }

    func export(runId: UUID) throws -> String {
        let store = try JSONLAlarmEventStore(directory: logsDirectory)
        return try store.export(runId: runId).joined(separator: "\n")
    }

    static func appStorage() throws -> LogExportService {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return LogExportService(logsDirectory: documents.appendingPathComponent("AlarmRuns", isDirectory: true))
    }
}

import Foundation
import SmartSleepCore

final class AlarmFileRepositoryAdapter: AlarmRepository, @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    func list() throws -> [Alarm] {
        try readAll().sorted(by: Self.sort(lhs:rhs:))
    }

    func alarm(id: UUID) throws -> Alarm? {
        try readAll().first { $0.id == id }
    }

    func save(_ alarm: Alarm) throws {
        var alarms = try readAll()
        alarms.removeAll { $0.id == alarm.id }
        alarms.append(alarm)
        try writeAll(alarms)
    }

    func delete(id: UUID) throws {
        var alarms = try readAll()
        alarms.removeAll { $0.id == id }
        try writeAll(alarms)
    }

    private func readAll() throws -> [Alarm] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([Alarm].self, from: data)
    }

    private func writeAll(_ alarms: [Alarm]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(alarms)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func sort(lhs: Alarm, rhs: Alarm) -> Bool {
        let lhsHour = lhs.timeOfDay.hour ?? 0
        let rhsHour = rhs.timeOfDay.hour ?? 0
        if lhsHour != rhsHour {
            return lhsHour < rhsHour
        }
        return (lhs.timeOfDay.minute ?? 0) < (rhs.timeOfDay.minute ?? 0)
    }

    static func appStorage() throws -> AlarmFileRepositoryAdapter {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return AlarmFileRepositoryAdapter(fileURL: documents.appendingPathComponent("alarms.json"))
    }
}

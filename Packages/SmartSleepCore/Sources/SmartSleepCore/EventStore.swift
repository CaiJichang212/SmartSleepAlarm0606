import Foundation

public enum AlarmEventRecord: Codable, Equatable, Sendable {
    case stateTransition(StateTransitionLog)
    case runtimeSession(RuntimeSessionLog)
    case channel(AlarmChannelLog)
    case sensorFreshness(SensorFreshness)
    case sensorSummary(SensorSummary)
    case gesture(GestureEvent)
    case outcome(OutcomeLabel)

    public var runId: UUID {
        switch self {
        case let .stateTransition(value): value.runId
        case let .runtimeSession(value): value.runId
        case let .channel(value): value.runId
        case let .sensorFreshness(value): value.runId
        case let .sensorSummary(value): value.runId
        case let .gesture(value): value.runId
        case let .outcome(value): value.runId
        }
    }
}

private struct JSONLEnvelope: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var recordedAt: Date
    var event: AlarmEventRecord
}

public final class JSONLAlarmEventStore: @unchecked Sendable {
    private let directory: URL
    private let encoder: JSONEncoder

    public init(directory: URL, encoder: JSONEncoder = JSONEncoder()) throws {
        self.directory = directory
        self.encoder = encoder
        self.encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func append(_ event: AlarmEventRecord, recordedAt: Date = Date()) throws {
        let envelope = JSONLEnvelope(schemaVersion: 1, recordedAt: recordedAt, event: event)
        var data = try encoder.encode(envelope)
        data.append(0x0A)

        let url = fileURL(for: event.runId)
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    public func export(runId: UUID) throws -> [String] {
        let url = fileURL(for: runId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let payload = try String(contentsOf: url, encoding: .utf8)
        return payload
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    private func fileURL(for runId: UUID) -> URL {
        directory.appendingPathComponent("\(runId.uuidString).jsonl")
    }
}


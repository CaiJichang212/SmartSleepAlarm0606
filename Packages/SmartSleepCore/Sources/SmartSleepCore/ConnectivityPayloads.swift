import Foundation

public struct AlarmConfigPayload: Codable, Equatable, Sendable {
    public var alarm: Alarm
    public var nextFireAt: Date

    public init(alarm: Alarm, nextFireAt: Date) {
        self.alarm = alarm
        self.nextFireAt = nextFireAt
    }
}

public struct ArmingResultPayload: Codable, Equatable, Sendable {
    public var alarmId: UUID
    public var armedAt: Date
    public var status: WatchArmingStatus

    public init(alarmId: UUID, armedAt: Date, status: WatchArmingStatus) {
        self.alarmId = alarmId
        self.armedAt = armedAt
        self.status = status
    }
}

public struct SessionResultPayload: Codable, Equatable, Sendable {
    public var alarmId: UUID
    public var runId: UUID
    public var state: SmartAlarmState
    public var scheduledAt: Date?
    public var failureReason: String?

    public init(
        alarmId: UUID,
        runId: UUID,
        state: SmartAlarmState,
        scheduledAt: Date?,
        failureReason: String?
    ) {
        self.alarmId = alarmId
        self.runId = runId
        self.state = state
        self.scheduledAt = scheduledAt
        self.failureReason = failureReason
    }
}

public struct RunLogSummaryPayload: Codable, Equatable, Sendable {
    public var runId: UUID
    public var finalState: SmartAlarmState
    public var outcome: OutcomeKind?
    public var eventCount: Int
    public var fallbackUsed: Bool

    public init(
        runId: UUID,
        finalState: SmartAlarmState,
        outcome: OutcomeKind?,
        eventCount: Int,
        fallbackUsed: Bool
    ) {
        self.runId = runId
        self.finalState = finalState
        self.outcome = outcome
        self.eventCount = eventCount
        self.fallbackUsed = fallbackUsed
    }
}

public enum SmartSleepConnectivityMessage: Codable, Equatable, Sendable {
    case alarmConfig(AlarmConfigPayload)
    case alarmCancelled(alarmId: UUID)
    case armingResult(ArmingResultPayload)
    case sessionResult(SessionResultPayload)
    case runLogSummary(RunLogSummaryPayload)
}

public enum ConnectivityDirection: String, Codable, Equatable, Sendable {
    case phoneToWatch
    case watchToPhone
}

public struct QueuedConnectivityMessage: Codable, Equatable, Sendable {
    public var message: SmartSleepConnectivityMessage
    public var direction: ConnectivityDirection
    public var queuedAt: Date

    public init(
        message: SmartSleepConnectivityMessage,
        direction: ConnectivityDirection,
        queuedAt: Date = Date()
    ) {
        self.message = message
        self.direction = direction
        self.queuedAt = queuedAt
    }
}

public final class MockSmartSleepTransport: @unchecked Sendable {
    public var isReachable: Bool
    public private(set) var deliveredMessages: [QueuedConnectivityMessage]
    public private(set) var outbox: [QueuedConnectivityMessage]

    public init(isReachable: Bool = true) {
        self.isReachable = isReachable
        self.deliveredMessages = []
        self.outbox = []
    }

    public func send(
        _ message: SmartSleepConnectivityMessage,
        direction: ConnectivityDirection,
        at queuedAt: Date = Date()
    ) throws {
        let queued = QueuedConnectivityMessage(
            message: message,
            direction: direction,
            queuedAt: queuedAt
        )

        if isReachable {
            deliveredMessages.append(queued)
        } else {
            outbox.append(queued)
        }
    }

    public func flushOutbox() {
        guard isReachable else { return }
        deliveredMessages.append(contentsOf: outbox)
        outbox.removeAll()
    }
}


import Foundation

public struct AlarmRunCoordinator: Sendable {
    public let runId: UUID
    private var machine: AlarmStateMachine
    private let eventStore: JSONLAlarmEventStore

    public init(
        runId: UUID = UUID(),
        initialState: SmartAlarmState = .idle,
        eventStore: JSONLAlarmEventStore
    ) {
        self.runId = runId
        self.machine = AlarmStateMachine(initialState: initialState)
        self.eventStore = eventStore
    }

    public var state: SmartAlarmState {
        machine.state
    }

    public mutating func apply(
        _ event: SmartAlarmEvent,
        reason: String,
        confidence: Double? = nil,
        featureSnapshotId: String? = nil,
        errorCode: String? = nil,
        timestamp: Date = Date()
    ) throws {
        let from = machine.state
        var nextMachine = machine
        try nextMachine.apply(event)
        let log = StateTransitionLog(
            runId: runId,
            fromState: from,
            toState: nextMachine.state,
            timestamp: timestamp,
            reason: reason,
            confidence: confidence,
            featureSnapshotId: featureSnapshotId,
            errorCode: errorCode
        )
        try eventStore.append(.stateTransition(log), recordedAt: timestamp)
        machine = nextMachine
    }

    public func appendChannelLog(_ log: AlarmChannelLog, timestamp: Date = Date()) throws {
        try eventStore.append(.channel(log), recordedAt: timestamp)
    }
}

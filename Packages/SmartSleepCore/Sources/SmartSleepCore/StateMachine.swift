import Foundation

public enum SmartAlarmState: String, Codable, CaseIterable, Sendable {
    case idle
    case createdOnPhone
    case needsWatchArming
    case armedOnWatch
    case sessionScheduled
    case preMonitoring
    case ringing
    case awakeCandidate
    case silencedMonitoring
    case reSleepRiskDetected
    case reRinging
    case snoozed
    case completed
    case fallbackPhoneAlarm
    case ringingNoSmart
    case sessionInvalidated
    case motionStale
    case watchNotWorn
    case lowBattery
    case completedWithFeedback
}

public enum SmartAlarmEvent: String, Codable, Sendable {
    case phoneCreatedAlarm
    case watchArmed
    case runtimeSessionScheduled
    case runtimeSessionFailed
    case preMonitoringStarted
    case motionBecameStale
    case watchNotWornDetected
    case lowBatteryDetected
    case ringTimeReached
    case awakeCandidateDetected
    case awakeConfirmed
    case candidateRejected
    case reSleepRiskDetected
    case reRingRequested
    case gestureSnoozeAccepted
    case userSnoozed
    case snoozeIntervalElapsed
    case userStopped
    case falseSilenceReported
}

public enum AlarmStateMachineError: Error, Equatable {
    case invalidTransition(from: SmartAlarmState, event: SmartAlarmEvent)
}

public struct AlarmStateMachine: Sendable {
    public private(set) var state: SmartAlarmState

    public init(initialState: SmartAlarmState = .idle) {
        self.state = initialState
    }

    public mutating func apply(_ event: SmartAlarmEvent) throws {
        guard let next = Self.transition(from: state, event: event) else {
            throw AlarmStateMachineError.invalidTransition(from: state, event: event)
        }
        state = next
    }

    public static func transition(from state: SmartAlarmState, event: SmartAlarmEvent) -> SmartAlarmState? {
        switch (state, event) {
        case (.idle, .phoneCreatedAlarm):
            return .needsWatchArming
        case (.createdOnPhone, .watchArmed), (.needsWatchArming, .watchArmed):
            return .armedOnWatch
        case (.needsWatchArming, .runtimeSessionFailed):
            return .fallbackPhoneAlarm
        case (.armedOnWatch, .runtimeSessionScheduled):
            return .sessionScheduled
        case (.armedOnWatch, .runtimeSessionFailed), (.sessionScheduled, .runtimeSessionFailed):
            return .fallbackPhoneAlarm
        case (.sessionScheduled, .preMonitoringStarted):
            return .preMonitoring
        case (.preMonitoring, .motionBecameStale):
            return .ringingNoSmart
        case (.preMonitoring, .watchNotWornDetected):
            return .fallbackPhoneAlarm
        case (.preMonitoring, .lowBatteryDetected):
            return .fallbackPhoneAlarm
        case (.preMonitoring, .ringTimeReached), (.sessionScheduled, .ringTimeReached):
            return .ringing
        case (.ringing, .awakeCandidateDetected), (.reRinging, .awakeCandidateDetected):
            return .awakeCandidate
        case (.awakeCandidate, .awakeConfirmed):
            return .silencedMonitoring
        case (.awakeCandidate, .candidateRejected):
            return .ringing
        case (.ringing, .gestureSnoozeAccepted), (.reRinging, .gestureSnoozeAccepted),
             (.ringing, .userSnoozed), (.reRinging, .userSnoozed):
            return .snoozed
        case (.snoozed, .snoozeIntervalElapsed):
            return .ringing
        case (.silencedMonitoring, .reSleepRiskDetected):
            return .reSleepRiskDetected
        case (.reSleepRiskDetected, .reRingRequested):
            return .reRinging
        case (.ringing, .userStopped), (.reRinging, .userStopped),
             (.silencedMonitoring, .userStopped), (.snoozed, .userStopped):
            return .completed
        case (.silencedMonitoring, .falseSilenceReported):
            return .completedWithFeedback
        default:
            return nil
        }
    }
}


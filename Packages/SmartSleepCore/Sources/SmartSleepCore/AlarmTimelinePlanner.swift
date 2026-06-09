import Foundation

public struct AlarmTimelinePlan: Codable, Equatable, Sendable {
    public var preMonitorTargetStartAt: Date
    public var secondsUntilRing: TimeInterval
    public var shouldStartRuntimeImmediately: Bool

    public init(
        preMonitorTargetStartAt: Date,
        secondsUntilRing: TimeInterval,
        shouldStartRuntimeImmediately: Bool
    ) {
        self.preMonitorTargetStartAt = preMonitorTargetStartAt
        self.secondsUntilRing = secondsUntilRing
        self.shouldStartRuntimeImmediately = shouldStartRuntimeImmediately
    }
}

public struct AlarmTimelinePlanner: Sendable {
    public var preMonitoringLeadTimeSec: TimeInterval

    public init(preMonitoringLeadTimeSec: TimeInterval = 30 * 60) {
        self.preMonitoringLeadTimeSec = preMonitoringLeadTimeSec
    }

    public func plan(nextFireAt: Date, now: Date) -> AlarmTimelinePlan {
        let targetStart = nextFireAt.addingTimeInterval(-preMonitoringLeadTimeSec)
        return AlarmTimelinePlan(
            preMonitorTargetStartAt: targetStart,
            secondsUntilRing: max(0, nextFireAt.timeIntervalSince(now)),
            shouldStartRuntimeImmediately: targetStart <= now
        )
    }
}

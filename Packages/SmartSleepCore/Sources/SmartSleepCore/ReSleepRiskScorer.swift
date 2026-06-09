import Foundation

public enum ReSleepReasonCode: String, Codable, CaseIterable, Sendable {
    case gracePeriod
    case lowMotion
    case stablePosture
    case noInteraction
    case noSteps
    case heartRateReturnBoost
    case maxReAlarmReached
    case lowRisk
    case motionStale
}

public struct ReSleepRiskResult: Codable, Equatable, Sendable {
    public var riskScore: Double
    public var shouldReRing: Bool
    public var reasonCodes: Set<ReSleepReasonCode>

    public init(riskScore: Double, shouldReRing: Bool, reasonCodes: Set<ReSleepReasonCode>) {
        self.riskScore = riskScore
        self.shouldReRing = shouldReRing
        self.reasonCodes = reasonCodes
    }
}

public struct ReSleepRiskScorer: Sendable {
    public var gracePeriodSec: Double
    public var highRiskThreshold: Double

    public init(gracePeriodSec: Double = 30, highRiskThreshold: Double = 0.8) {
        self.gracePeriodSec = gracePeriodSec
        self.highRiskThreshold = highRiskThreshold
    }

    public func evaluate(
        monitoringElapsedSec: Double,
        summary: SensorSummary,
        freshness: SensorFreshness,
        reAlarmCount: Int,
        maxReAlarmCount: Int
    ) -> ReSleepRiskResult {
        var score = 0.0
        var reasons: Set<ReSleepReasonCode> = []

        guard monitoringElapsedSec >= gracePeriodSec else {
            return ReSleepRiskResult(riskScore: 0, shouldReRing: false, reasonCodes: [.gracePeriod])
        }

        guard freshness.motionFresh else {
            return ReSleepRiskResult(riskScore: 0, shouldReRing: false, reasonCodes: [.motionStale])
        }

        if reAlarmCount >= maxReAlarmCount {
            return ReSleepRiskResult(riskScore: 0, shouldReRing: false, reasonCodes: [.maxReAlarmReached])
        }

        if summary.stillnessDurationSec >= 90 {
            score += 0.35
            reasons.insert(.lowMotion)
        }

        if summary.postureDelta < 10 {
            score += 0.20
            reasons.insert(.stablePosture)
        }

        if summary.interactionCount == 0 && summary.screenWakeCount == 0 {
            score += 0.20
            reasons.insert(.noInteraction)
        }

        if summary.stepDelta == 0 {
            score += 0.15
            reasons.insert(.noSteps)
        }

        if freshness.heartRateUsable, let hrDelta = summary.hrDeltaFromBaseline, hrDelta <= 3 {
            score += 0.10
            reasons.insert(.heartRateReturnBoost)
        }

        let risk = min(score, 1)
        let shouldReRing = risk >= highRiskThreshold
        if !shouldReRing {
            reasons.insert(.lowRisk)
        }

        return ReSleepRiskResult(riskScore: risk, shouldReRing: shouldReRing, reasonCodes: reasons)
    }
}

import Foundation

public enum AwakeReasonCode: String, Codable, CaseIterable, Sendable {
    case motionContinuity
    case postureChange
    case wristRotation
    case stepDelta
    case userInteraction
    case heartRateFreshBoost
    case heartRateOnlyRejected
    case motionStale
    case watchNotWorn
    case lowConfidence
}

public struct AwakeScoreResult: Codable, Equatable, Sendable {
    public var score: Double
    public var confidence: Double
    public var shouldAutoSilence: Bool
    public var reasonCodes: Set<AwakeReasonCode>
}

public struct AwakeScorer: Sendable {
    public var highConfidenceThreshold: Double

    public init(highConfidenceThreshold: Double = 0.8) {
        self.highConfidenceThreshold = highConfidenceThreshold
    }

    public func evaluate(summary: SensorSummary, freshness: SensorFreshness) -> AwakeScoreResult {
        var score = 0.0
        var reasonCodes: Set<AwakeReasonCode> = []
        var motionTriggered = false

        guard freshness.motionFresh else {
            return AwakeScoreResult(
                score: 0,
                confidence: 0,
                shouldAutoSilence: false,
                reasonCodes: [.motionStale]
            )
        }

        guard freshness.watchWornConfidence >= .medium else {
            return AwakeScoreResult(
                score: 0,
                confidence: 0,
                shouldAutoSilence: false,
                reasonCodes: [.watchNotWorn]
            )
        }

        if summary.motionContinuitySec >= 10 {
            score += 0.35
            motionTriggered = true
            reasonCodes.insert(.motionContinuity)
        }

        if summary.postureDelta >= 45 {
            score += 0.20
            motionTriggered = true
            reasonCodes.insert(.postureChange)
        }

        if summary.gyroPeak >= 3 {
            score += 0.15
            motionTriggered = true
            reasonCodes.insert(.wristRotation)
        }

        if summary.stepDelta > 0 {
            score += 0.15
            motionTriggered = true
            reasonCodes.insert(.stepDelta)
        }

        if summary.screenWakeCount > 0 || summary.interactionCount > 0 {
            score += 0.15
            motionTriggered = true
            reasonCodes.insert(.userInteraction)
        }

        if freshness.heartRateUsable, let hrDelta = summary.hrDeltaFromBaseline, hrDelta >= 12 {
            score += 0.10
            reasonCodes.insert(.heartRateFreshBoost)
        }

        if !motionTriggered && reasonCodes == [.heartRateFreshBoost] {
            reasonCodes.insert(.heartRateOnlyRejected)
        }

        let confidence = min(score, 1)
        let shouldAutoSilence = confidence >= highConfidenceThreshold
            && motionTriggered
            && !reasonCodes.contains(.heartRateOnlyRejected)

        if !shouldAutoSilence && !reasonCodes.contains(.heartRateOnlyRejected) {
            reasonCodes.insert(.lowConfidence)
        }

        return AwakeScoreResult(
            score: score,
            confidence: confidence,
            shouldAutoSilence: shouldAutoSilence,
            reasonCodes: reasonCodes
        )
    }
}


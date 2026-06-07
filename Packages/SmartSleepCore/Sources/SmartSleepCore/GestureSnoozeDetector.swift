import Foundation

public enum RotationDirection: String, Codable, Sendable {
    case clockwise
    case counterClockwise
}

public struct RotationSample: Codable, Equatable, Sendable {
    public var timestampOffsetSec: Double
    public var direction: RotationDirection
    public var gyroPeak: Double
    public var postureDelta: Double

    public init(timestampOffsetSec: Double, direction: RotationDirection, gyroPeak: Double, postureDelta: Double) {
        self.timestampOffsetSec = timestampOffsetSec
        self.direction = direction
        self.gyroPeak = gyroPeak
        self.postureDelta = postureDelta
    }
}

public enum GestureRejectionReason: String, Codable, Equatable, Sendable {
    case invalidState
    case cooldown
    case motionStale
    case insufficientRotations
    case inconsistentDirection
    case belowThreshold
    case outsideWindow
}

public struct GestureDetectionResult: Codable, Equatable, Sendable {
    public var accepted: Bool
    public var confidence: Double
    public var rotationPeak: Double
    public var directionConsistency: Double
    public var cooldownPassed: Bool
    public var rejectionReason: GestureRejectionReason?
}

public struct GestureSnoozeDetector: Sendable {
    public var cooldownSec: Double
    public var gestureWindowSec: Double
    public var minGyroPeak: Double
    public var minPostureDelta: Double
    public var minDirectionConsistency: Double

    public init(
        cooldownSec: Double = 1.5,
        gestureWindowSec: Double = 1.5,
        minGyroPeak: Double = 3.0,
        minPostureDelta: Double = 25,
        minDirectionConsistency: Double = 1.0
    ) {
        self.cooldownSec = cooldownSec
        self.gestureWindowSec = gestureWindowSec
        self.minGyroPeak = minGyroPeak
        self.minPostureDelta = minPostureDelta
        self.minDirectionConsistency = minDirectionConsistency
    }

    public func evaluate(
        state: SmartAlarmState,
        ringingElapsedSec: Double,
        motionFresh: Bool,
        samples: [RotationSample]
    ) -> GestureDetectionResult {
        let cooldownPassed = ringingElapsedSec >= cooldownSec
        let rotationPeak = samples.map(\.gyroPeak).max() ?? 0
        let directionConsistency = Self.directionConsistency(samples)

        guard state == .ringing || state == .reRinging else {
            return rejected(.invalidState, rotationPeak, directionConsistency, cooldownPassed)
        }
        guard cooldownPassed else {
            return rejected(.cooldown, rotationPeak, directionConsistency, cooldownPassed)
        }
        guard motionFresh else {
            return rejected(.motionStale, rotationPeak, directionConsistency, cooldownPassed)
        }
        guard samples.count >= 2 else {
            return rejected(.insufficientRotations, rotationPeak, directionConsistency, cooldownPassed)
        }
        guard let first = samples.map(\.timestampOffsetSec).min(),
              let last = samples.map(\.timestampOffsetSec).max(),
              last - first <= gestureWindowSec else {
            return rejected(.outsideWindow, rotationPeak, directionConsistency, cooldownPassed)
        }
        guard directionConsistency >= minDirectionConsistency else {
            return rejected(.inconsistentDirection, rotationPeak, directionConsistency, cooldownPassed)
        }
        guard rotationPeak >= minGyroPeak,
              samples.allSatisfy({ $0.postureDelta >= minPostureDelta }) else {
            return rejected(.belowThreshold, rotationPeak, directionConsistency, cooldownPassed)
        }

        let confidence = min(1, (rotationPeak / minGyroPeak) * 0.6 + directionConsistency * 0.4)
        return GestureDetectionResult(
            accepted: true,
            confidence: confidence,
            rotationPeak: rotationPeak,
            directionConsistency: directionConsistency,
            cooldownPassed: cooldownPassed,
            rejectionReason: nil
        )
    }

    private func rejected(
        _ reason: GestureRejectionReason,
        _ rotationPeak: Double,
        _ directionConsistency: Double,
        _ cooldownPassed: Bool
    ) -> GestureDetectionResult {
        GestureDetectionResult(
            accepted: false,
            confidence: 0,
            rotationPeak: rotationPeak,
            directionConsistency: directionConsistency,
            cooldownPassed: cooldownPassed,
            rejectionReason: reason
        )
    }

    private static func directionConsistency(_ samples: [RotationSample]) -> Double {
        guard let first = samples.first else { return 0 }
        let matching = samples.filter { $0.direction == first.direction }.count
        return Double(matching) / Double(samples.count)
    }
}


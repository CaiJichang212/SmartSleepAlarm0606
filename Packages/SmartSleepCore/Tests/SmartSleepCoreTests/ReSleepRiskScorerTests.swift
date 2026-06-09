import XCTest
@testable import SmartSleepCore

final class ReSleepRiskScorerTests: XCTestCase {
    func testGracePeriodPreventsReRinging() {
        let result = ReSleepRiskScorer().evaluate(
            monitoringElapsedSec: 20,
            summary: SensorSummary.fixture(
                motionContinuitySec: 0,
                postureDelta: 1,
                gyroPeak: 0,
                stepDelta: 0,
                interactionCount: 0,
                hrDeltaFromBaseline: nil
            ),
            freshness: SensorFreshness.fixture(
                motionLastSampleAgeSec: 1,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                watchWornConfidence: .medium
            ),
            reAlarmCount: 0,
            maxReAlarmCount: 2
        )

        XCTAssertFalse(result.shouldReRing)
        XCTAssertTrue(result.reasonCodes.contains(.gracePeriod))
    }

    func testHighStillnessRiskTriggersAfterGracePeriod() {
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        summary.stillnessDurationSec = 150

        let result = ReSleepRiskScorer().evaluate(
            monitoringElapsedSec: 180,
            summary: summary,
            freshness: SensorFreshness.fixture(
                motionLastSampleAgeSec: 1,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                watchWornConfidence: .medium
            ),
            reAlarmCount: 0,
            maxReAlarmCount: 2
        )

        XCTAssertTrue(result.shouldReRing)
        XCTAssertGreaterThanOrEqual(result.riskScore, 0.8)
        XCTAssertTrue(result.reasonCodes.contains(.lowMotion))
        XCTAssertTrue(result.reasonCodes.contains(.noInteraction))
    }

    func testMaxReAlarmCountPreventsInfiniteReRinging() {
        var summary = SensorSummary.fixture(
            motionContinuitySec: 0,
            postureDelta: 1,
            gyroPeak: 0,
            stepDelta: 0,
            interactionCount: 0,
            hrDeltaFromBaseline: nil
        )
        summary.stillnessDurationSec = 180

        let result = ReSleepRiskScorer().evaluate(
            monitoringElapsedSec: 240,
            summary: summary,
            freshness: SensorFreshness.fixture(
                motionLastSampleAgeSec: 1,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                watchWornConfidence: .medium
            ),
            reAlarmCount: 2,
            maxReAlarmCount: 2
        )

        XCTAssertFalse(result.shouldReRing)
        XCTAssertTrue(result.reasonCodes.contains(.maxReAlarmReached))
    }
}

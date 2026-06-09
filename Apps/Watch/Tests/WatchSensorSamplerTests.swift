import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchSensorSamplerTests: XCTestCase {
    func testMotionWindowAggregatorBuildsSummaryFromSamples() {
        var aggregator = MotionWindowAggregator(
            runId: UUID(),
            windowStart: Date(timeIntervalSince1970: 0)
        )
        aggregator.append(MotionWindowSample(
            timestamp: Date(timeIntervalSince1970: 1),
            accelMagnitude: 0.1,
            gyroMagnitude: 0.2,
            attitudeRoll: 0,
            attitudePitch: 0,
            attitudeYaw: 0
        ))
        aggregator.append(MotionWindowSample(
            timestamp: Date(timeIntervalSince1970: 2),
            accelMagnitude: 1.0,
            gyroMagnitude: 3.5,
            attitudeRoll: 0.8,
            attitudePitch: 0,
            attitudeYaw: 0
        ))

        let summary = aggregator.summary(windowEnd: Date(timeIntervalSince1970: 3))

        XCTAssertGreaterThan(summary.accelMagnitudeMean, 0.5)
        XCTAssertEqual(summary.gyroPeak, 3.5, accuracy: 0.001)
        XCTAssertGreaterThan(summary.postureDelta, 40)
    }

    func testFakeSamplerEmitsMotionFreshness() {
        let runId = UUID()
        let sampler = FakeWatchSensorSampler()
        var received: SensorFreshness?
        sampler.onFreshness = { received = $0 }

        sampler.start(runId: runId)
        sampler.emitFreshness(
            SensorFreshness(
                runId: runId,
                timestamp: Date(timeIntervalSince1970: 10),
                motionSampleCount: 30,
                motionLastSampleAgeSec: 1,
                hrSampleCount: 0,
                hrLastSampleAgeSec: nil,
                baselineHRConfidence: .none,
                baselineMotionConfidence: .medium,
                watchWornConfidence: .medium,
                sensorConfidence: .medium
            )
        )

        XCTAssertEqual(received?.runId, runId)
        XCTAssertEqual(received?.motionLastSampleAgeSec, 1)
        XCTAssertTrue(received?.motionFresh == true)
    }
}

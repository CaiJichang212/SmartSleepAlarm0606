import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

@MainActor
final class WatchSensorSamplerTests: XCTestCase {
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

import XCTest
@testable import SmartSleepWatch
import SmartSleepCore

final class WatchHealthKitHeartRateSamplerTests: XCTestCase {
    func testFreshHeartRateMapsToUsableFreshnessValues() {
        let runId = UUID()
        let now = Date(timeIntervalSince1970: 200)
        let sample = HeartRateSample(
            bpm: 72,
            sampledAt: Date(timeIntervalSince1970: 140),
            baselineBPM: 60,
            baselineConfidence: .medium
        )

        let freshness = HeartRateFreshnessMapper.freshness(
            runId: runId,
            now: now,
            sample: sample,
            motionSampleCount: 20,
            motionLastSampleAgeSec: 1,
            watchWornConfidence: .medium
        )

        XCTAssertEqual(freshness.hrSampleCount, 1)
        XCTAssertEqual(freshness.hrLastSampleAgeSec, 60)
        XCTAssertEqual(freshness.baselineHRConfidence, .medium)
        XCTAssertTrue(freshness.heartRateUsable)
    }

    func testDeniedAuthorizationDoesNotDisableMotionFreshness() async {
        let sampler = FakeWatchHeartRateSampler(
            authorization: .denied,
            latestHeartRateSample: nil
        )

        let authorization = await sampler.authorizationState()
        let freshness = HeartRateFreshnessMapper.freshness(
            runId: UUID(),
            now: Date(timeIntervalSince1970: 200),
            sample: sampler.latestHeartRateSample,
            motionSampleCount: 20,
            motionLastSampleAgeSec: 1,
            watchWornConfidence: .medium
        )

        XCTAssertEqual(authorization, .denied)
        XCTAssertEqual(freshness.hrSampleCount, 0)
        XCTAssertFalse(freshness.heartRateUsable)
        XCTAssertTrue(freshness.motionFresh)
    }
}

final class FakeWatchHeartRateSampler: WatchHeartRateSampling {
    private let authorization: AuthorizationState
    private(set) var latestHeartRateSample: HeartRateSample?

    init(authorization: AuthorizationState, latestHeartRateSample: HeartRateSample?) {
        self.authorization = authorization
        self.latestHeartRateSample = latestHeartRateSample
    }

    func authorizationState() async -> AuthorizationState { authorization }
    func start() {}
    func stop() {}
}

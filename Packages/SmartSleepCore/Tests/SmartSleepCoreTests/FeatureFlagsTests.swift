import XCTest
@testable import SmartSleepCore

final class FeatureFlagsTests: XCTestCase {
    func testDefaultFlagsKeepExperimentalBehaviorConservative() {
        let flags = FeatureFlags.v02Default

        XCTAssertFalse(flags.autoSilenceEnabled)
        XCTAssertFalse(flags.reSleepDetectionEnabled)
        XCTAssertTrue(flags.gestureSnoozeEnabled)
        XCTAssertTrue(flags.heartRateBoostEnabled)
        XCTAssertEqual(flags.maxReAlarmCount, 2)
    }
}

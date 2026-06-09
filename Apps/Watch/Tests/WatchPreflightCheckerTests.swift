import XCTest
@testable import SmartSleepWatch

final class WatchPreflightCheckerTests: XCTestCase {
    func testPastAlarmTimeFailsPreflightWithInjectedNow() {
        let checker = WatchPreflightChecker()

        let result = checker.check(
            nextFireAt: Date(timeIntervalSince1970: 100),
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertFalse(result.canArmSmartMode)
        XCTAssertEqual(result.failureReason, "alarm_time_not_in_future")
    }
}

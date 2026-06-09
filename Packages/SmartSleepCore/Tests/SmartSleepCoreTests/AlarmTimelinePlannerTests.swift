import XCTest
@testable import SmartSleepCore

final class AlarmTimelinePlannerTests: XCTestCase {
    func testPreMonitoringStartsThirtyMinutesBeforeFireTime() {
        let fireAt = Date(timeIntervalSince1970: 3_600)
        let plan = AlarmTimelinePlanner().plan(nextFireAt: fireAt, now: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(plan.preMonitorTargetStartAt, Date(timeIntervalSince1970: 1_800))
        XCTAssertEqual(plan.secondsUntilRing, 3_600)
        XCTAssertFalse(plan.shouldStartRuntimeImmediately)
    }

    func testStartsImmediatelyWhenPreMonitoringWindowAlreadyOpened() {
        let fireAt = Date(timeIntervalSince1970: 3_600)
        let plan = AlarmTimelinePlanner().plan(nextFireAt: fireAt, now: Date(timeIntervalSince1970: 2_000))

        XCTAssertEqual(plan.preMonitorTargetStartAt, Date(timeIntervalSince1970: 1_800))
        XCTAssertEqual(plan.secondsUntilRing, 1_600)
        XCTAssertTrue(plan.shouldStartRuntimeImmediately)
    }
}

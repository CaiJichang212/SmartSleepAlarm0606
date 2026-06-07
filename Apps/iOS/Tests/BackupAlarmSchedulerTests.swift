import XCTest
@testable import SmartSleepAlarm
import SmartSleepCore

final class BackupAlarmSchedulerTests: XCTestCase {
    func testRepeatingAlarmBuildsOneRequestPerWeekday() throws {
        var alarm = Alarm.fixture(smartEnabled: true)
        alarm.repeatDays = [.monday, .wednesday, .friday]
        let nextFireAt = Date(timeIntervalSince1970: 3_600)

        let requests = BackupAlarmScheduler.makeRequests(for: alarm, nextFireAt: nextFireAt)

        XCTAssertEqual(requests.count, 3)
        let weekdays = requests.compactMap {
            ($0.trigger as? UNCalendarNotificationTrigger)?
                .dateComponents
                .weekday
        }
        XCTAssertEqual(Set(weekdays), Set([2, 4, 6]))
    }

    func testNonRepeatingAlarmBuildsSingleRequestWithoutWeekday() throws {
        var alarm = Alarm.fixture(smartEnabled: true)
        alarm.repeatDays = []
        let nextFireAt = Date(timeIntervalSince1970: 3_600)
        let expectedComponents = Calendar.current.dateComponents([.hour, .minute], from: nextFireAt)

        let requests = BackupAlarmScheduler.makeRequests(for: alarm, nextFireAt: nextFireAt)

        XCTAssertEqual(requests.count, 1)
        let components = try XCTUnwrap((requests[0].trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        XCTAssertNil(components.weekday)
        XCTAssertEqual(components.hour, expectedComponents.hour)
        XCTAssertEqual(components.minute, expectedComponents.minute)
    }
}

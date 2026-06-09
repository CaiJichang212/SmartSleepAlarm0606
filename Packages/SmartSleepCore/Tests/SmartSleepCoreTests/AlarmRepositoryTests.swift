import XCTest
@testable import SmartSleepCore

final class AlarmRepositoryTests: XCTestCase {
    func testMemoryRepositoryCreatesListsUpdatesAndDeletesAlarms() throws {
        let repository = MemoryAlarmRepository()
        let alarm = Alarm.fixture(smartEnabled: true)

        try repository.save(alarm)
        XCTAssertEqual(try repository.list(), [alarm])

        var disabled = alarm
        disabled.isEnabled = false
        try repository.save(disabled)
        XCTAssertEqual(try repository.alarm(id: alarm.id)?.isEnabled, false)

        try repository.delete(id: alarm.id)
        XCTAssertEqual(try repository.list(), [])
    }

    func testMemoryRepositorySortsByTimeOfDay() throws {
        let repository = MemoryAlarmRepository()
        var later = Alarm.fixture(smartEnabled: true)
        later.timeOfDay = DateComponents(hour: 8, minute: 15)

        var earlier = Alarm.fixture(smartEnabled: true)
        earlier.id = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        earlier.timeOfDay = DateComponents(hour: 6, minute: 45)

        try repository.save(later)
        try repository.save(earlier)

        XCTAssertEqual(try repository.list().map(\.id), [earlier.id, later.id])
    }
}

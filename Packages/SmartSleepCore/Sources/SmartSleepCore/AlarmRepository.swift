import Foundation

public protocol AlarmRepository {
    func list() throws -> [Alarm]
    func alarm(id: UUID) throws -> Alarm?
    func save(_ alarm: Alarm) throws
    func delete(id: UUID) throws
}

public final class MemoryAlarmRepository: AlarmRepository {
    private var storage: [UUID: Alarm]

    public init(alarms: [Alarm] = []) {
        self.storage = Dictionary(uniqueKeysWithValues: alarms.map { ($0.id, $0) })
    }

    public func list() throws -> [Alarm] {
        storage.values.sorted(by: Self.sort(lhs:rhs:))
    }

    public func alarm(id: UUID) throws -> Alarm? {
        storage[id]
    }

    public func save(_ alarm: Alarm) throws {
        storage[alarm.id] = alarm
    }

    public func delete(id: UUID) throws {
        storage.removeValue(forKey: id)
    }

    private static func sort(lhs: Alarm, rhs: Alarm) -> Bool {
        let lhsHour = lhs.timeOfDay.hour ?? 0
        let rhsHour = rhs.timeOfDay.hour ?? 0
        if lhsHour != rhsHour {
            return lhsHour < rhsHour
        }
        return (lhs.timeOfDay.minute ?? 0) < (rhs.timeOfDay.minute ?? 0)
    }
}

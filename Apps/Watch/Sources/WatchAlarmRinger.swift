import Foundation
import WatchKit

protocol WatchAlarmRinging {
    func startRinging()
    func snooze()
    func stop()
}

final class FakeWatchAlarmRinger: WatchAlarmRinging {
    private(set) var startCallCount = 0
    private(set) var snoozeCallCount = 0
    private(set) var stopCallCount = 0

    func startRinging() {
        startCallCount += 1
    }

    func snooze() {
        snoozeCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }
}

struct WatchAlarmRinger: WatchAlarmRinging {
    func startRinging() {
        WKInterfaceDevice.current().play(.notification)
    }

    func snooze() {
        WKInterfaceDevice.current().play(.directionDown)
    }

    func stop() {
        WKInterfaceDevice.current().play(.success)
    }
}

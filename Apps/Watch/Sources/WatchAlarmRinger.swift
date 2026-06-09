import Foundation
import WatchKit

protocol WatchAlarmRinging {
    func startRinging()
    func snooze()
    func stop()
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

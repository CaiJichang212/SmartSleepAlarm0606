import CoreMotion
import Foundation
import WatchKit

struct WatchPreflightResult: Equatable, Sendable {
    var canArmSmartMode: Bool
    var batteryLevel: Double?
    var motionAvailable: Bool
    var failureReason: String?
}

protocol WatchPreflightChecking {
    func check(nextFireAt: Date, now: Date) -> WatchPreflightResult
}

struct WatchPreflightChecker: WatchPreflightChecking {
    func check(nextFireAt: Date, now: Date = Date()) -> WatchPreflightResult {
        let device = WKInterfaceDevice.current()
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = Double(device.batteryLevel)
        let motionAvailable = CMMotionManager().isDeviceMotionAvailable

        if batteryLevel >= 0, batteryLevel < 0.10 {
            return WatchPreflightResult(
                canArmSmartMode: false,
                batteryLevel: batteryLevel,
                motionAvailable: motionAvailable,
                failureReason: "watch_battery_low"
            )
        }

        if nextFireAt <= now {
            return WatchPreflightResult(
                canArmSmartMode: false,
                batteryLevel: batteryLevel >= 0 ? batteryLevel : nil,
                motionAvailable: motionAvailable,
                failureReason: "alarm_time_not_in_future"
            )
        }

        if !motionAvailable {
            return WatchPreflightResult(
                canArmSmartMode: false,
                batteryLevel: batteryLevel >= 0 ? batteryLevel : nil,
                motionAvailable: false,
                failureReason: "motion_unavailable"
            )
        }

        return WatchPreflightResult(
            canArmSmartMode: true,
            batteryLevel: batteryLevel >= 0 ? batteryLevel : nil,
            motionAvailable: motionAvailable,
            failureReason: nil
        )
    }
}

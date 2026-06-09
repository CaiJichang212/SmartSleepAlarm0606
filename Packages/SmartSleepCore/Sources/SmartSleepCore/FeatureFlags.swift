import Foundation

public struct FeatureFlags: Codable, Equatable, Sendable {
    public var autoSilenceEnabled: Bool
    public var reSleepDetectionEnabled: Bool
    public var gestureSnoozeEnabled: Bool
    public var heartRateBoostEnabled: Bool
    public var maxReAlarmCount: Int

    public init(
        autoSilenceEnabled: Bool,
        reSleepDetectionEnabled: Bool,
        gestureSnoozeEnabled: Bool,
        heartRateBoostEnabled: Bool,
        maxReAlarmCount: Int
    ) {
        self.autoSilenceEnabled = autoSilenceEnabled
        self.reSleepDetectionEnabled = reSleepDetectionEnabled
        self.gestureSnoozeEnabled = gestureSnoozeEnabled
        self.heartRateBoostEnabled = heartRateBoostEnabled
        self.maxReAlarmCount = maxReAlarmCount
    }

    public static let v02Default = FeatureFlags(
        autoSilenceEnabled: false,
        reSleepDetectionEnabled: false,
        gestureSnoozeEnabled: true,
        heartRateBoostEnabled: true,
        maxReAlarmCount: 2
    )
}

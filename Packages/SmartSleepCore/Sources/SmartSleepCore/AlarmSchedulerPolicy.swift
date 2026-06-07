import Foundation

public struct AlarmSchedulingDecision: Equatable, Sendable {
    public var smartModeStatus: SmartModeStatus
    public var shouldSyncToWatch: Bool
    public var shouldSchedulePhoneBackup: Bool
    public var requiredBackupChannel: AlarmChannel

    public init(
        smartModeStatus: SmartModeStatus,
        shouldSyncToWatch: Bool,
        shouldSchedulePhoneBackup: Bool,
        requiredBackupChannel: AlarmChannel
    ) {
        self.smartModeStatus = smartModeStatus
        self.shouldSyncToWatch = shouldSyncToWatch
        self.shouldSchedulePhoneBackup = shouldSchedulePhoneBackup
        self.requiredBackupChannel = requiredBackupChannel
    }
}

public struct AlarmSchedulerPolicy: Sendable {
    public init() {}

    public func decision(for alarm: Alarm, arming: WatchArmingStatus?) -> AlarmSchedulingDecision {
        let status = SmartModeResolver.status(for: alarm, arming: arming)
        return AlarmSchedulingDecision(
            smartModeStatus: status,
            shouldSyncToWatch: alarm.isEnabled && alarm.smartEnabled,
            shouldSchedulePhoneBackup: alarm.isEnabled,
            requiredBackupChannel: .iOSLocalNotification
        )
    }
}

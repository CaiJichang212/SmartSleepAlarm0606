import Foundation

public struct AlarmSchedulingDecision: Equatable, Sendable {
    public var smartModeStatus: SmartModeStatus
    public var shouldSyncToWatch: Bool
    public var shouldSchedulePhoneBackup: Bool
    public var requiredBackupChannel: AlarmChannel
    public var fallbackUserVisibleState: String
    public var fallbackRiskMessage: String?
    public var requiresManualFallbackPrompt: Bool

    public init(
        smartModeStatus: SmartModeStatus,
        shouldSyncToWatch: Bool,
        shouldSchedulePhoneBackup: Bool,
        requiredBackupChannel: AlarmChannel,
        fallbackUserVisibleState: String,
        fallbackRiskMessage: String?,
        requiresManualFallbackPrompt: Bool
    ) {
        self.smartModeStatus = smartModeStatus
        self.shouldSyncToWatch = shouldSyncToWatch
        self.shouldSchedulePhoneBackup = shouldSchedulePhoneBackup
        self.requiredBackupChannel = requiredBackupChannel
        self.fallbackUserVisibleState = fallbackUserVisibleState
        self.fallbackRiskMessage = fallbackRiskMessage
        self.requiresManualFallbackPrompt = requiresManualFallbackPrompt
    }
}

public struct AlarmSchedulerPolicy: Sendable {
    private let backupChannelPolicy: BackupChannelPolicy

    public init(backupChannelPolicy: BackupChannelPolicy = BackupChannelPolicy()) {
        self.backupChannelPolicy = backupChannelPolicy
    }

    public func decision(for alarm: Alarm, arming: WatchArmingStatus?) -> AlarmSchedulingDecision {
        decision(for: alarm, arming: arming, capabilities: .localNotificationDefault)
    }

    public func decision(
        for alarm: Alarm,
        arming: WatchArmingStatus?,
        capabilities: BackupChannelCapabilities
    ) -> AlarmSchedulingDecision {
        let status = SmartModeResolver.status(for: alarm, arming: arming)
        let fallback = backupChannelPolicy.decision(
            preferred: alarm.backupChannelPreferred,
            capabilities: capabilities
        )

        return AlarmSchedulingDecision(
            smartModeStatus: status,
            shouldSyncToWatch: alarm.isEnabled && alarm.smartEnabled,
            shouldSchedulePhoneBackup: alarm.isEnabled,
            requiredBackupChannel: fallback.channel,
            fallbackUserVisibleState: fallback.userVisibleState,
            fallbackRiskMessage: fallback.riskMessage,
            requiresManualFallbackPrompt: fallback.requiresManualFallbackPrompt
        )
    }
}

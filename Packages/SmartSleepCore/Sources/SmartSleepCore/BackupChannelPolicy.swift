import Foundation

public struct BackupChannelCapabilities: Codable, Equatable, Sendable {
    public var alarmKitSupported: Bool
    public var alarmKitAuthorization: AuthorizationState
    public var notificationAuthorization: AuthorizationState
    public var foregroundAudioAvailable: Bool

    public init(
        alarmKitSupported: Bool,
        alarmKitAuthorization: AuthorizationState,
        notificationAuthorization: AuthorizationState,
        foregroundAudioAvailable: Bool
    ) {
        self.alarmKitSupported = alarmKitSupported
        self.alarmKitAuthorization = alarmKitAuthorization
        self.notificationAuthorization = notificationAuthorization
        self.foregroundAudioAvailable = foregroundAudioAvailable
    }

    public static let localNotificationDefault = BackupChannelCapabilities(
        alarmKitSupported: false,
        alarmKitAuthorization: .unavailable,
        notificationAuthorization: .unknown,
        foregroundAudioAvailable: false
    )
}

public struct BackupChannelDecision: Codable, Equatable, Sendable {
    public var channel: AlarmChannel
    public var userVisibleState: String
    public var riskMessage: String?
    public var requiresManualFallbackPrompt: Bool

    public init(
        channel: AlarmChannel,
        userVisibleState: String,
        riskMessage: String?,
        requiresManualFallbackPrompt: Bool
    ) {
        self.channel = channel
        self.userVisibleState = userVisibleState
        self.riskMessage = riskMessage
        self.requiresManualFallbackPrompt = requiresManualFallbackPrompt
    }
}

public struct BackupChannelPolicy: Sendable {
    public init() {}

    public func decision(
        preferred: AlarmChannel,
        capabilities: BackupChannelCapabilities
    ) -> BackupChannelDecision {
        if preferred == .iOSAlarmKit,
           capabilities.alarmKitSupported,
           capabilities.alarmKitAuthorization == .authorized {
            return BackupChannelDecision(
                channel: .iOSAlarmKit,
                userVisibleState: "alarmkit_ready",
                riskMessage: nil,
                requiresManualFallbackPrompt: false
            )
        }

        if capabilities.notificationAuthorization == .authorized ||
            capabilities.notificationAuthorization == .notDetermined ||
            capabilities.notificationAuthorization == .unknown {
            let state: String
            let message: String?

            if capabilities.notificationAuthorization == .authorized {
                state = capabilities.alarmKitSupported
                    ? "alarmkit_denied_local_notification"
                    : "alarmkit_unavailable_local_notification"
                message = capabilities.alarmKitSupported
                    ? "AlarmKit is denied; iPhone fallback uses Local Notification with lower reliability."
                    : "AlarmKit is unavailable on this device; iPhone fallback uses Local Notification with lower reliability."
            } else {
                state = "notification_authorization_unknown"
                message = nil
            }

            return BackupChannelDecision(
                channel: .iOSLocalNotification,
                userVisibleState: state,
                riskMessage: message,
                requiresManualFallbackPrompt: false
            )
        }

        if capabilities.foregroundAudioAvailable {
            return BackupChannelDecision(
                channel: .foregroundAudio,
                userVisibleState: "foreground_audio_only",
                riskMessage: "Notifications are denied; fallback audio works only while the iPhone app stays in foreground.",
                requiresManualFallbackPrompt: true
            )
        }

        return BackupChannelDecision(
            channel: .manualFallbackPrompt,
            userVisibleState: "manual_system_alarm_required",
            riskMessage: "No automatic iPhone fallback is authorized; ask the user to set a system alarm.",
            requiresManualFallbackPrompt: true
        )
    }
}

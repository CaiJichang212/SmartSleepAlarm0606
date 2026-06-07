import Foundation
import SmartSleepCore
import UserNotifications

protocol NotificationAuthorizing {
    func requestAuthorization() async throws -> AuthorizationState
    func authorizationState() async -> AuthorizationState
}

struct NotificationPermissionService: NotificationAuthorizing {
    func requestAuthorization() async throws -> AuthorizationState {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        )
        return granted ? .authorized : .denied
    }

    func authorizationState() async -> AuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unknown
        }
    }
}

struct FakeNotificationAuthorizer: NotificationAuthorizing {
    var state: AuthorizationState

    func requestAuthorization() async throws -> AuthorizationState {
        state
    }

    func authorizationState() async -> AuthorizationState {
        state
    }
}

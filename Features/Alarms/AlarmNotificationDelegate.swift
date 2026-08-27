import Foundation
import Observation
import UserNotifications

/// Bridges `UNUserNotificationCenter` callbacks (which aren't SwiftUI-aware)
/// into an `@Observable` property the view hierarchy can react to. Set as
/// `UNUserNotificationCenter.current().delegate` once, in
/// `AppDependencies.init`.
@MainActor
@Observable
final class AlarmNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private(set) var activeAlarmID: UUID?

    func clearActiveAlarm() {
        activeAlarmID = nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            handle(notification.request.content.userInfo)
        }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            handle(response.notification.request.content.userInfo)
        }
        completionHandler()
    }

    private func handle(_ userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["alarmID"] as? String, let id = UUID(uuidString: raw) else { return }
        activeAlarmID = id
    }
}

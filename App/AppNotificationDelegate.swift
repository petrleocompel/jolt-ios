import Foundation
import Observation
import UserNotifications

/// Bridges `UNUserNotificationCenter` callbacks (which aren't SwiftUI-aware)
/// into either an `@Observable` property the view hierarchy reacts to
/// (alarms — needs to present a full-screen dismissal flow) or a direct
/// action (pokes — just fire the stimulus, no screen to show). Set as
/// `UNUserNotificationCenter.current().delegate` once, in
/// `AppDependencies.init`.
@MainActor
@Observable
final class AppNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private(set) var activeAlarmID: UUID?
    private let pokeRepository: PokeRepository
    private let pushDiagnostics: PushDiagnosticsRepository

    init(pokeRepository: PokeRepository, pushDiagnostics: PushDiagnosticsRepository) {
        self.pokeRepository = pokeRepository
        self.pushDiagnostics = pushDiagnostics
    }

    func clearActiveAlarm() {
        activeAlarmID = nil
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            await handle(notification.request.content.userInfo, path: .foreground)
        }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            await handle(response.notification.request.content.userInfo, path: .alert)
        }
        completionHandler()
    }

    /// `path` distinguishes a notification the user tapped from one shown
    /// while the app was already open — a test push reports which one saw it.
    private func handle(_ userInfo: [AnyHashable: Any], path: TestPushPath) async {
        if let raw = userInfo["alarmID"] as? String, let id = UUID(uuidString: raw) {
            activeAlarmID = id
            return
        }
        if let payload = TestPushPayload(userInfo: userInfo) {
            await pushDiagnostics.handleIncomingTestPush(payload, path: path)
            return
        }
        if let payload = PokePushPayload(userInfo: userInfo) {
            await pokeRepository.handleIncomingPoke(payload)
        }
    }
}

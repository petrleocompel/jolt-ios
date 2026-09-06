import UIKit

/// Bridges the handful of push-notification callbacks that have no pure
/// SwiftUI equivalent: raw device-token registration and background silent
/// (`content-available`) pushes. Everything else (foreground presentation,
/// notification taps) goes through `AppNotificationDelegate` via
/// `UNUserNotificationCenterDelegate` instead.
final class JoltAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            AppDependencies.shared?.apnsToken = token
            await AppDependencies.shared?.authRepository.registerPushToken(token)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("[Jolt] Failed to register for remote notifications: \(error)")
        #endif
    }

    /// Best-effort background fire path for a silent push (see delivery
    /// model in docs/openapi.yaml). iOS gives this a tight, unpredictable
    /// execution budget and can coalesce/delay it by minutes — the alert
    /// half of the push (handled by `AppNotificationDelegate` on tap) is
    /// what guarantees the recipient ever finds out, this is the "maybe it
    /// fires without you touching anything" bonus.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // A diagnostic push takes the same silent path a poke does — that is
        // the point of it, since this is the half of delivery that tends to
        // break quietly.
        if let test = TestPushPayload(userInfo: userInfo) {
            Task { @MainActor in
                await AppDependencies.shared?.pushDiagnostics
                    .handleIncomingTestPush(test, path: .background)
                completionHandler(.newData)
            }
            return
        }
        guard let payload = PokePushPayload(userInfo: userInfo) else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            let status = await AppDependencies.shared?.pokeRepository.handleIncomingPoke(payload)
            completionHandler(status == .fired ? .newData : .failed)
        }
    }
}

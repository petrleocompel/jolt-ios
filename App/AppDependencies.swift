import Foundation
import Observation
import SwiftData
import UserNotifications

/// Composition root. Built once in `JoltApp.init` and threaded down through
/// the environment; feature view models take protocol types out of this so
/// they stay swappable (e.g. for previews or tests).
@MainActor
@Observable
final class AppDependencies {
    /// `JoltAppDelegate` can't be constructed with dependencies injected
    /// (UIKit owns its lifecycle via `@UIApplicationDelegateAdaptor`), so it
    /// reads this at the moment a remote notification actually arrives
    /// instead. The one deliberate exception to "everything flows through
    /// the environment" in this codebase.
    static private(set) var shared: AppDependencies?

    let deviceRepository: DeviceRepository
    let alarmRepository: AlarmRepository
    let phoneAlarmScheduler: PhoneAlarmScheduler
    let authRepository: AuthRepository
    let friendsRepository: FriendsRepository
    let pokeRepository: PokeRepository
    let notificationDelegate: AppNotificationDelegate
    let modelContainer: ModelContainer
    /// Which server the social features are talking to. Nil in snapshot mode
    /// and whenever the mock backend is in use.
    let serverConfiguration: ServerConfiguration?

    /// Set by `ServerSettingsView` after a server change. The backend is
    /// built once here against a fixed base URL, so the switch only takes
    /// effect on the next launch — Settings says so rather than appearing to
    /// do nothing.
    var pendingServerRestartNotice = false

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: AlarmEntity.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
        self.modelContainer = container
        self.alarmRepository = SwiftDataAlarmRepository(modelContainer: container)
        self.phoneAlarmScheduler = PhoneAlarmScheduler()
        self.deviceRepository = AppEnvironment.isSnapshotMode
            ? FakeDeviceRepository()
            : CompositeDeviceRepository()

        // Snapshot runs must stay hermetic — the screenshot runner has no
        // network and no server. Everything else talks to the configured
        // Jolt server, which is ours by default and self-hosted if the user
        // has pointed Settings elsewhere.
        let social: AuthRepository & FriendsRepository & PokeRepository
        if AppEnvironment.isSnapshotMode {
            self.serverConfiguration = nil
            social = MockSocialBackend(deviceRepository: deviceRepository)
        } else {
            let configuration = ServerSettingsStore().load()
            self.serverConfiguration = configuration
            social = HTTPSocialBackend(
                configuration: configuration,
                deviceRepository: deviceRepository
            )
        }
        self.authRepository = social
        self.friendsRepository = social
        self.pokeRepository = social

        let delegate = AppNotificationDelegate(pokeRepository: social)
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        Self.shared = self
    }
}

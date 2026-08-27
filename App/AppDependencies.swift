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

        let social = MockSocialBackend(deviceRepository: deviceRepository)
        self.authRepository = social
        self.friendsRepository = social
        self.pokeRepository = social

        let delegate = AppNotificationDelegate(pokeRepository: social)
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        Self.shared = self
    }
}

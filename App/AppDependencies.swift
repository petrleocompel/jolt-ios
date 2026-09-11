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
    /// Settings → Notifications: "did the push actually get here?".
    let pushDiagnostics: PushDiagnosticsRepository
    /// Approach A: turns a wearable button gesture into an outgoing friend
    /// poke. Runs for the app's lifetime, subscribing only while a device is
    /// connected and the trigger is enabled.
    let pokeTriggerService: PokeTriggerService
    /// Settings → Quick Poke: a one-tap poke button on the Remote tab for a
    /// friend chosen ahead of time.
    let quickPokeService: QuickPokeService
    /// Settings → Firing: per-stimulus tap / hold / confirm for Remote rows
    /// and poke controls.
    let firingModeService: FiringModeService
    /// Settings → Poke feedback: banner / flash / haptic / label after a
    /// successful outgoing poke.
    let pokeFeedbackService: PokeFeedbackService
    /// Last kind + intensity per friend for the poke composer.
    let friendPokeDraftStore: FriendPokeDraftStore
    /// Remote tab → Customize: widget order/visibility on the dashboard.
    let remoteDashboardLayoutService: RemoteDashboardLayoutService
    let notificationDelegate: AppNotificationDelegate
    let modelContainer: ModelContainer
    /// Which server the social features are talking to. Nil in snapshot mode
    /// and whenever the mock backend is in use.
    let serverConfiguration: ServerConfiguration?

    /// This device's APNs token, as handed to `JoltAppDelegate` on launch.
    /// Nil until Apple answers, or forever if the user declined notifications
    /// — which is itself worth showing on the notification test screen.
    var apnsToken: String?

    /// Set by `ServerSettingsView` after a server change. The backend is
    /// built once here against a fixed base URL, so the switch only takes
    /// effect on the next launch — Settings says so rather than appearing to
    /// do nothing.
    var pendingServerRestartNotice = false

    init() {
        Self.resetPersistedStateIfSnapshotMode()

        let container = Self.makeModelContainer()
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
        let socialStack = Self.makeSocialStack(deviceRepository: deviceRepository)
        self.serverConfiguration = socialStack.configuration
        let social = socialStack.backend
        self.authRepository = social
        self.friendsRepository = social
        self.pokeRepository = social
        self.pushDiagnostics = social

        let triggerService = PokeTriggerService(
            deviceRepository: deviceRepository,
            pokeRepository: social
        )
        self.pokeTriggerService = triggerService
        // Safe in snapshot mode: FakeDeviceRepository never connects, so the
        // service simply idles.
        triggerService.start()

        let pokeFeedback = PokeFeedbackService()
        self.pokeFeedbackService = pokeFeedback
        self.friendPokeDraftStore = FriendPokeDraftStore()
        self.quickPokeService = QuickPokeService(
            pokeRepository: social,
            feedback: pokeFeedback
        )
        self.firingModeService = FiringModeService()
        self.remoteDashboardLayoutService = RemoteDashboardLayoutService()

        let delegate = AppNotificationDelegate(pokeRepository: social, pushDiagnostics: social)
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        Self.shared = self
    }

    private typealias SocialBackend =
        AuthRepository & FriendsRepository & PokeRepository & PushDiagnosticsRepository

    private static func makeModelContainer() -> ModelContainer {
        do {
            if AppEnvironment.isSnapshotMode {
                // Hermetic, non-accumulating store seeded with demo alarms so
                // the Alarms screenshot isn't an empty state.
                let container = try ModelContainer(
                    for: AlarmEntity.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
                seedSnapshotAlarms(into: container)
                return container
            }
            return try ModelContainer(for: AlarmEntity.self)
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    private static func makeSocialStack(
        deviceRepository: DeviceRepository
    ) -> (configuration: ServerConfiguration?, backend: SocialBackend) {
        if AppEnvironment.isSnapshotMode {
            return (nil, MockSocialBackend(deviceRepository: deviceRepository))
        }
        let configuration = ServerSettingsStore().load()
        return (
            configuration,
            HTTPSocialBackend(configuration: configuration, deviceRepository: deviceRepository)
        )
    }

    /// Every `UserDefaults`-backed store in the app (`PokeTriggerStore`,
    /// `QuickPokeSettingsStore`, `StimulusSettingsStore`, ...) persists to
    /// `.standard`, which survives an app relaunch — including between
    /// separate UI test methods run back to back on the same simulator.
    /// Without this, a test that enables the poke trigger (or any other
    /// saved setting) leaves that flipped for whichever test runs next,
    /// making outcomes depend on run order/history instead of the app under
    /// test. Same "hermetic, non-accumulating" treatment as the in-memory
    /// SwiftData container in `init`, for the same reason.
    private static func resetPersistedStateIfSnapshotMode() {
        guard AppEnvironment.isSnapshotMode, let bundleID = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }

    /// Two believable device alarms for the App Store / marketing screenshot,
    /// inserted straight into the in-memory snapshot store. Never runs outside
    /// snapshot mode.
    private static func seedSnapshotAlarms(into container: ModelContainer) {
        let weekdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let demo: [Alarm] = [
            Alarm(
                location: .device, hour: 7, minute: 0, repeatDays: weekdays,
                label: "Wake up", stimulus: StimulusConfig(kind: .zap, intensity: 40),
                dismissChallenge: .qrCodeScan
            ),
            Alarm(
                location: .device, hour: 14, minute: 30, repeatDays: weekdays,
                label: "Stand up", stimulus: StimulusConfig(kind: .vibe, intensity: 60)
            )
        ]
        let context = container.mainContext
        for alarm in demo {
            if let entity = alarm.makeEntity() {
                context.insert(entity)
            }
        }
        try? context.save()
    }
}

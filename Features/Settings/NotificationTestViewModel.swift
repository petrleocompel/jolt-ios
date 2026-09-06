import Foundation
import Observation
import UIKit
import UserNotifications

/// Drives Settings → Notifications: what iOS and the server each think is set
/// up, and the round trip that proves it.
///
/// The confirmation is read back from the *server*, not observed locally, on
/// purpose. Watching the push arrive in-process would prove only that this
/// process got it; polling `GET /devices/test-push/{id}` proves the ack made
/// it back, which is the same thing the web dashboard sees.
@MainActor
@Observable
final class NotificationTestViewModel {
    /// How long to wait for a confirmation before calling it undelivered.
    /// A locked phone usually answers in under a second; iOS can sit on the
    /// silent half far longer, and past this it isn't worth staring at.
    private static let confirmationWindow: Duration = .seconds(30)

    private let repository: PushDiagnosticsRepository
    private var pollTask: Task<Void, Never>?

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var devices: [RegisteredDevice] = []
    private(set) var status: TestPushStatus?
    private(set) var isSending = false
    /// True while the confirmation window is open — the difference between
    /// "no answer yet" and "no answer".
    private(set) var isWaiting = false
    var errorMessage: String?

    var fireOnPavlok = false
    var stimulus = StimulusConfig(kind: .vibe, intensity: 20)

    /// Set by the view from `AppDependencies`, which learns it from Apple
    /// asynchronously after launch.
    var apnsToken: String?

    init(repository: PushDiagnosticsRepository) {
        self.repository = repository
    }

    /// The row in `devices` that is this phone, matched on the token tail the
    /// server exposes. Nil before Apple has answered, or when this device has
    /// never registered against the current server.
    var thisDevice: RegisteredDevice? {
        guard let suffix = apnsToken?.suffix(8), !suffix.isEmpty else { return nil }
        return devices.first { $0.tokenSuffix == String(suffix) }
    }

    var isRegistered: Bool { thisDevice != nil }

    /// What the last test amounts to for the device it was sent to. Nil when
    /// nothing has been sent yet.
    var outcome: Outcome? {
        guard let status else { return nil }
        if let failure = status.devices.first(where: { !$0.isAccepted }) {
            return .rejected(reason: failure.detail ?? failure.reason ?? "unknown")
        }
        if let ack = status.acks.first {
            return .delivered(ack)
        }
        if !status.apnsConfigured {
            return .notConfigured
        }
        return isWaiting ? .waiting : .noConfirmation
    }

    enum Outcome: Equatable {
        case waiting
        case delivered(TestPushAck)
        /// Apple refused the token outright — nothing was ever sent.
        case rejected(reason: String)
        /// The window closed with no word from any device.
        case noConfirmation
        /// The server has no Apple credentials, so nothing will ever arrive.
        case notConfigured
    }

    func refresh() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus
        devices = (try? await repository.registeredDevices()) ?? []
    }

    /// Prompts, then re-registers: a token only arrives once notifications are
    /// allowed, so the two always go together.
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        // Launch already asked; asking again is what actually produces a token
        // now that the user has said yes.
        UIApplication.shared.registerForRemoteNotifications()
        await refresh()
    }

    func send() async {
        pollTask?.cancel()
        isSending = true
        errorMessage = nil
        status = nil
        defer { isSending = false }

        do {
            // Target this phone when we can identify it — on an account with
            // several devices, "did it reach *this* one" is the question being
            // asked. Fall back to all of them when we can't.
            status = try await repository.sendTestPush(
                to: thisDevice?.id,
                stimulus: fireOnPavlok ? stimulus : nil
            )
            isWaiting = true
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
        }
        // A rejected token may have just been disabled server-side.
        await refresh()
    }

    func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
        isWaiting = false
    }

    private func startPolling() {
        guard let testID = status?.testID else { return }
        pollTask = Task { [weak self] in
            let deadline = ContinuousClock.now.advanced(by: Self.confirmationWindow)
            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                // A 404 means the server forgot the test (or never had one, as
                // with the mock backend). The last state we hold is still the
                // useful one, so stop rather than clearing it.
                guard let refreshed = try? await self.repository.testPushStatus(testID) else {
                    break
                }
                self.status = refreshed
                if !refreshed.acks.isEmpty { break }
            }
            self?.isWaiting = false
        }
    }
}

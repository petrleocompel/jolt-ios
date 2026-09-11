import Foundation
import Observation
import UIKit

/// Plays and surfaces the user-configured poke success feedback (banner,
/// flash, haptic, temporary "Sent" label). Shared between Quick Poke on
/// Remote and the Friends composer.
@MainActor
@Observable
final class PokeFeedbackService {
    private let store: PokeFeedbackSettingsStore

    private(set) var settings: PokeFeedbackSettings
    private(set) var lastSuccessMessage: String?
    private(set) var isFlashing = false
    private(set) var isShowingSuccessLabel = false

    @ObservationIgnored
    private var bannerResetTask: Task<Void, Never>?
    @ObservationIgnored
    private var flashResetTask: Task<Void, Never>?
    @ObservationIgnored
    private var labelResetTask: Task<Void, Never>?

    init(store: PokeFeedbackSettingsStore = PokeFeedbackSettingsStore()) {
        self.store = store
        self.settings = store.load()
    }

    func update(_ newSettings: PokeFeedbackSettings) {
        settings = newSettings
        store.save(newSettings)
    }

    func applyProfile(_ profile: PokeFeedbackProfile) {
        var updated = settings
        updated.applyProfile(profile)
        update(updated)
    }

    func setShowBanner(_ value: Bool) {
        mutateToggle { $0.showBanner = value }
    }

    func setFlashButton(_ value: Bool) {
        mutateToggle { $0.flashButton = value }
    }

    func setPlayHaptic(_ value: Bool) {
        mutateToggle { $0.playHaptic = value }
    }

    func setSwapButtonLabel(_ value: Bool) {
        mutateToggle { $0.swapButtonLabel = value }
    }

    /// Call after a poke POST succeeds. No-ops individually when the matching
    /// toggle is off — so tap / hold / confirm all share one success path.
    func noteSuccess(message: String) {
        if settings.playHaptic {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        if settings.showBanner {
            lastSuccessMessage = message
            bannerResetTask?.cancel()
            bannerResetTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.lastSuccessMessage = nil
            }
        }

        if settings.flashButton {
            isFlashing = true
            flashResetTask?.cancel()
            flashResetTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                self?.isFlashing = false
            }
        }

        if settings.swapButtonLabel {
            isShowingSuccessLabel = true
            labelResetTask?.cancel()
            labelResetTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.isShowingSuccessLabel = false
            }
        }
    }

    func clearSuccessMessage() {
        lastSuccessMessage = nil
        bannerResetTask?.cancel()
    }

    private func mutateToggle(_ body: (inout PokeFeedbackSettings) -> Void) {
        var updated = settings
        body(&updated)
        updated.reconcileProfile()
        update(updated)
    }
}

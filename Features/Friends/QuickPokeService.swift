import Foundation
import Observation

/// Backs the Remote-tab "quick poke" button: holds the configured target
/// friend/stimulus (via `QuickPokeSettingsStore`) and sends through the
/// normal poke path when tapped.
///
/// Constructed once in `AppDependencies` and shared between the Remote tab
/// and its Settings screen, so a change made in one shows up in the other
/// immediately.
@MainActor
@Observable
final class QuickPokeService {
    private let pokeRepository: PokeRepository
    private let store: QuickPokeSettingsStore

    private(set) var settings: QuickPokeSettings
    private(set) var lastPokeSentAt: Date?
    var lastError: String?

    init(
        pokeRepository: PokeRepository,
        store: QuickPokeSettingsStore = QuickPokeSettingsStore()
    ) {
        self.pokeRepository = pokeRepository
        self.store = store
        self.settings = store.load()
    }

    // MARK: Settings-facing mutations

    func update(_ newSettings: QuickPokeSettings) {
        settings = newSettings
        store.save(newSettings)
    }

    func setEnabled(_ enabled: Bool) {
        var updated = settings
        updated.isEnabled = enabled
        update(updated)
    }

    func setTarget(friendID: Friend.ID, name: String) {
        var updated = settings
        updated.targetFriendID = friendID
        updated.targetFriendName = name
        update(updated)
    }

    func setStimulus(_ stimulus: StimulusConfig) {
        var updated = settings
        updated.stimulus = stimulus
        update(updated)
    }

    // MARK: Remote-tab action

    func sendQuickPoke() {
        guard let friendID = settings.targetFriendID else { return }
        lastError = nil
        let stimulus = settings.stimulus
        Task { [weak self] in
            guard let self else { return }
            do {
                try await pokeRepository.sendPoke(to: friendID, stimulus: stimulus)
                self.lastPokeSentAt = Date()
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }
}

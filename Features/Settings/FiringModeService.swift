import Foundation
import Observation

/// Holds the user's chosen `FiringInteractionMode` and keeps every fire-able
/// control in sync — constructed once in `AppDependencies` and shared between
/// the Remote tab, the poke composer, and its own Settings row, mirroring how
/// `QuickPokeService` shares its settings.
@MainActor
@Observable
final class FiringModeService {
    private let store: FiringInteractionSettingsStore

    private(set) var mode: FiringInteractionMode

    init(store: FiringInteractionSettingsStore = FiringInteractionSettingsStore()) {
        self.store = store
        self.mode = store.load()
    }

    func setMode(_ mode: FiringInteractionMode) {
        self.mode = mode
        store.save(mode)
    }
}

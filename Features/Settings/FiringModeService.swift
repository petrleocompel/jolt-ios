import Foundation
import Observation

/// Holds per-stimulus `FiringInteractionMode` values and keeps every fire-able
/// control in sync — constructed once in `AppDependencies` and shared between
/// the Remote tab, the poke composer, and Settings.
@MainActor
@Observable
final class FiringModeService {
    private let store: FiringInteractionSettingsStore

    private(set) var settings: FiringInteractionSettings

    init(store: FiringInteractionSettingsStore = FiringInteractionSettingsStore()) {
        self.store = store
        self.settings = store.load()
    }

    func mode(for kind: StimulusKind) -> FiringInteractionMode {
        settings[kind]
    }

    func setMode(_ mode: FiringInteractionMode, for kind: StimulusKind) {
        settings[kind] = mode
        store.save(settings)
    }

    func update(_ newSettings: FiringInteractionSettings) {
        settings = newSettings
        store.save(newSettings)
    }
}

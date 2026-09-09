import Foundation

/// Persists the one `FiringInteractionMode` (see it for what and why).
///
/// `UserDefaults`, like `QuickPokeSettingsStore` / `ServerSettingsStore` — a
/// single small value read at launch and rewritten from Settings. A raw-value
/// string rather than JSON since there's only ever one scalar to store.
struct FiringInteractionSettingsStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.firingInteractionMode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FiringInteractionMode {
        guard let raw = defaults.string(forKey: key),
              let mode = FiringInteractionMode(rawValue: raw) else {
            return .default
        }
        return mode
    }

    func save(_ mode: FiringInteractionMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

import Foundation

/// Persists the one `QuickPokeSettings` (see it for what and why).
///
/// `UserDefaults`, like `PokeTriggerStore` / `ServerSettingsStore` — a single
/// small value read at launch and rewritten from Settings.
struct QuickPokeSettingsStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.quickPoke"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> QuickPokeSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(QuickPokeSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: QuickPokeSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

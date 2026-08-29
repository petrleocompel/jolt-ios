import Foundation

/// Persists the one `PokeTrigger` (see it for what and why).
///
/// `UserDefaults`, like `ServerSettingsStore` / `StimulusSettingsStore` — a
/// single small value read at launch and rewritten from Settings.
struct PokeTriggerStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.pokeTrigger"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PokeTrigger {
        guard let data = defaults.data(forKey: key),
              let trigger = try? JSONDecoder().decode(PokeTrigger.self, from: data) else {
            return .default
        }
        return trigger
    }

    func save(_ trigger: PokeTrigger) {
        guard let data = try? JSONEncoder().encode(trigger) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

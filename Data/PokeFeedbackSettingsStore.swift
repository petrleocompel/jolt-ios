import Foundation

struct PokeFeedbackSettingsStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.pokeFeedback"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PokeFeedbackSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(PokeFeedbackSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: PokeFeedbackSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

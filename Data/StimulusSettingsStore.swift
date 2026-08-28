import Foundation

/// Persists per-kind stimulus defaults across launches.
///
/// `UserDefaults` rather than SwiftData: this is three small structs read on
/// nearly every screen and written from a slider, which is the shape
/// `UserDefaults` is for. Same reasoning as `PairedDeviceStore`.
struct StimulusSettingsStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.stimulusSettings"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> StimulusSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(StimulusSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save(_ settings: StimulusSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

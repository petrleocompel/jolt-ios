import Foundation

/// Persists `FiringInteractionSettings` (per-stimulus firing modes).
///
/// Migrates the older single-mode `UserDefaults` string so existing users keep
/// their chosen gesture across the upgrade to per-kind modes.
struct FiringInteractionSettingsStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.firingInteractionSettings"
    private let legacyKey = "cz.peelco.jolt.firingInteractionMode"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> FiringInteractionSettings {
        if let data = defaults.data(forKey: key),
           let settings = try? JSONDecoder().decode(FiringInteractionSettings.self, from: data) {
            return settings
        }
        if let raw = defaults.string(forKey: legacyKey),
           let mode = FiringInteractionMode(rawValue: raw) {
            return .uniform(mode)
        }
        return .default
    }

    func save(_ settings: FiringInteractionSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
        // Drop the legacy scalar so a later load doesn't resurrect a stale
        // uniform value if the JSON blob is ever cleared.
        defaults.removeObject(forKey: legacyKey)
    }
}

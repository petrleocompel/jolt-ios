import Foundation

/// Persists which server the app talks to.
///
/// `UserDefaults`, like `PairedDeviceStore` and `StimulusSettingsStore` — one
/// small value read at launch. The auth *token* for that server is a
/// different matter and lives in the keychain (`AuthTokenStore`).
struct ServerSettingsStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.serverConfiguration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ServerConfiguration {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(ServerConfiguration.self, from: data) else {
            return .default
        }
        return config
    }

    func save(_ configuration: ServerConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }

    /// True when the user has pointed the app at something other than the
    /// bundled default — surfaced in Settings so it's obvious at a glance.
    var isCustom: Bool {
        load() != .default
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

import Foundation

/// Persists the one `RemoteDashboardLayout` (see it for what and why).
///
/// `UserDefaults` + JSON, like `QuickPokeSettingsStore` — a single small
/// value read at launch and rewritten from the Customize screen.
struct RemoteDashboardLayoutStore {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.remoteDashboardLayout"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RemoteDashboardLayout {
        guard let data = defaults.data(forKey: key),
              let layout = try? JSONDecoder().decode(RemoteDashboardLayout.self, from: data) else {
            return .default
        }
        return layout.reconciled()
    }

    func save(_ layout: RemoteDashboardLayout) {
        guard let data = try? JSONEncoder().encode(layout) else { return }
        defaults.set(data, forKey: key)
    }
}

import Foundation

/// How long the relay asked the app to leave it alone (`429 rate_limited`,
/// protocol C21). Kept in `UserDefaults` rather than memory: relaunching the
/// app inside the window must not count as having waited.
///
/// One for the relay as a whole, not per endpoint: the relay limits by
/// client address, so a refused registration says the same about the
/// challenge and unregistering.
struct RelayBackoff {
    private let defaults: UserDefaults
    private let key = "cz.peelco.jolt.relayBackoffUntil"
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    /// When the wait ends, while one is running.
    var until: Date? {
        guard let date = defaults.object(forKey: key) as? Date, date > now() else { return nil }
        return date
    }

    /// Starts a wait of `seconds`, never shortening one already running.
    func wait(_ seconds: TimeInterval) {
        let end = now().addingTimeInterval(seconds)
        if let until, until >= end { return }
        defaults.set(end, forKey: key)
    }
}

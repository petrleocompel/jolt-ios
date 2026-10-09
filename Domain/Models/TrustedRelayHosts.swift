import Foundation

/// The relays this build will register with. A self-hosted server names its
/// relay in `GET /push/config`, but it doesn't get to pick an arbitrary one:
/// registering hands the relay this phone's APNs token, so only relays on the
/// built-in list are used (relay protocol section 8).
///
/// Comes from the `JoltTrustedRelayHosts` Info.plist key, i.e. the
/// `JOLT_TRUSTED_RELAY_HOSTS` build setting, so the official builds name
/// their relay in CI configuration rather than in the source.
struct TrustedRelayHosts: Equatable {
    let hosts: Set<String>

    static let bundled = TrustedRelayHosts(
        infoValue: Bundle.main.object(forInfoDictionaryKey: "JoltTrustedRelayHosts")
    )

    init(_ hosts: [String]) {
        self.hosts = Set(hosts.map { $0.lowercased() }.filter { !$0.isEmpty })
    }

    /// Host names separated by spaces or commas. Anything else — missing, not
    /// a string, an unexpanded build setting — trusts nothing.
    init(infoValue: Any?) {
        guard let string = infoValue as? String, !string.contains("$(") else {
            self.init([])
            return
        }
        self.init(string.components(separatedBy: CharacterSet(charactersIn: ", ").union(.whitespacesAndNewlines)))
    }

    /// HTTPS on the default port to a listed host, and nothing smuggled in
    /// the authority: a user name or password in the URL is refused rather
    /// than reasoned about.
    func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host()?.lowercased(), hosts.contains(host),
              url.port == nil || url.port == 443,
              url.user() == nil, url.password() == nil else { return false }
        return true
    }
}

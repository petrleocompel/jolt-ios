import Foundation

/// Everything the relay path of push registration needs besides the Jolt
/// server, gathered so tests can replace it: which relays to trust, App
/// Attest, where keys and the registration are kept, and the network.
@MainActor
struct RelayEnvironment {
    var trustedHosts: TrustedRelayHosts
    var attestor: AppAttesting
    var keys: PayloadKeyStore
    var registrations: RelayRegistrationStore
    var session: URLSession
    /// The bundle ID the relay checks against its allow-list.
    var appId: String
    /// `production` or `sandbox`: which APNs environment issued this build's
    /// tokens.
    var apnsEnvironment: String
    /// How long the relay has asked to be left alone (C21).
    var backoff = RelayBackoff()

    static var live: RelayEnvironment {
        RelayEnvironment(
            trustedHosts: .bundled,
            attestor: AppAttestor(),
            keys: PayloadKeyStore(),
            registrations: RelayRegistrationStore(),
            session: .shared,
            appId: Bundle.main.bundleIdentifier ?? "cz.peelco.jolt",
            apnsEnvironment: apnsEnvironment(from: Bundle.main.object(forInfoDictionaryKey: "JoltAPSEnvironment"))
        )
    }

    /// The entitlement says `development`, the relay says `sandbox`.
    static func apnsEnvironment(from infoValue: Any?) -> String {
        infoValue as? String == "development" ? "sandbox" : "production"
    }
}

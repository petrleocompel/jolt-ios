import Foundation

/// How the signed-in server sends pushes, from `GET /push/config` (relay
/// protocol section 7). Decides what this phone registers, and with whom.
struct PushConfig: Decodable, Equatable {
    enum Transport: String, Decodable {
        /// The server holds its own APNs credentials: register the APNs token
        /// with the server directly, as every build before the relay did.
        case apns
        /// Register with the relay named in `relay`, then hand the server the
        /// relay's token and a key it can't use anywhere else.
        case relay
        /// Push isn't configured on the server. Nothing to register.
        case none
    }

    struct Relay: Decodable, Equatable {
        var url: URL
        var serverId: String
    }

    var transport: Transport
    /// Present only for `apns`.
    var apnsEnvironment: String?
    /// Present only for `relay`.
    var relay: Relay?

    /// What a server that predates the endpoint (a 404) means: its own APNs
    /// credentials or none at all, and it can't say which, so register
    /// directly exactly as before.
    static let legacy = PushConfig(transport: .apns)
}

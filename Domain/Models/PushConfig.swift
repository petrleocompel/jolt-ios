import Foundation

/// How the signed-in server sends pushes, from `GET /push/config` (relay
/// protocol section 7). Decides what this phone registers, and with whom.
struct PushConfig: Decodable, Equatable {
    enum Transport: Decodable, Equatable {
        /// The server holds its own APNs credentials: register the APNs token
        /// with the server directly, as every build before the relay did.
        case apns
        /// Register with the relay named in `relay`, then hand the server the
        /// relay's token and a key it can't use anywhere else.
        case relay
        /// Push isn't configured on the server. Nothing to register.
        case none
        /// A route this build doesn't know. Treated as an error that leaves
        /// the current registration alone (C18), not as a reason to fail the
        /// whole answer.
        case unsupported(String)

        init(from decoder: Decoder) throws {
            switch try decoder.singleValueContainer().decode(String.self) {
            case "apns": self = .apns
            case "relay": self = .relay
            case "none": self = .none
            case let other: self = .unsupported(other)
            }
        }
    }

    typealias Relay = PushRelayEndpoint

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

/// Where a relayed server's pushes come from: `relay` in `GET /push/config`.
struct PushRelayEndpoint: Decodable, Equatable {
    /// Always ends in `/`; see `RelayClient.normalizedBaseURL`.
    var url: URL
    var serverId: String

    init(url: URL, serverId: String) {
        self.url = RelayClient.normalizedBaseURL(url)
        self.serverId = serverId
    }

    private enum CodingKeys: String, CodingKey {
        case url, serverId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            url: try container.decode(URL.self, forKey: .url),
            serverId: try container.decode(String.self, forKey: .serverId)
        )
    }
}

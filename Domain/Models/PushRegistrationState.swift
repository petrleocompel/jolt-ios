import Foundation

/// How pushes reach this phone, for Settings → Notifications.
enum PushTransport: Equatable {
    /// Not settled yet: signed out, no token from Apple, or the server
    /// couldn't be asked.
    case unknown
    /// Registered with the server directly.
    case apns
    /// Registered through the relay, for the server with this `serverId`.
    case relay(serverId: String)
    /// The server has no push configured.
    case none

    var displayName: String {
        switch self {
        case .unknown: return "Not known yet"
        case .apns: return "Direct APNs"
        case .relay: return "Relay"
        case .none: return "None"
        }
    }
}

struct PushRegistrationState: Equatable {
    var transport: PushTransport = .unknown
    /// What the server knows this phone by: the APNs token, or the relay's
    /// token for it. Nil until a registration has gone through.
    var registeredToken: String?
    /// Why it hasn't, when it should have.
    var problem: String?

    var serverId: String? {
        if case .relay(let serverId) = transport { return serverId }
        return nil
    }
}

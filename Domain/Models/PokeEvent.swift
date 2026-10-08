import Foundation

enum PokeDirection: String, Codable {
    case sent
    case received
}

enum PokeDeliveryStatus: String, Codable {
    /// Accepted and pushed, but no device has acked yet. Every poke is
    /// created with this status; every other value is terminal and is only
    /// ever set by the recipient's ack. iOS gives no delivery guarantee for
    /// the silent push, so a poke can legitimately stay `pending` forever.
    case pending
    /// Reached the device and fired.
    case fired
    /// Push arrived (or was simulated) but the recipient's device wasn't
    /// connected to fire it on.
    case deviceNotConnected
    /// Sender's permission grant didn't allow this stimulus/intensity —
    /// surfaced so the sender knows it was silently capped/blocked, not lost.
    case notAllowed
    /// Recipient had "Do not disturb incoming pokes" on — distinct from
    /// `deviceNotConnected` so the activity log reads correctly.
    case muted
}

struct PokeEvent: Identifiable, Codable, Equatable {
    var id: UUID
    var direction: PokeDirection
    var friendHandle: String
    var friendDisplayName: String
    var stimulus: StimulusConfig
    var status: PokeDeliveryStatus
    var createdAt: Date
    /// When the recipient's device reported back — i.e. when `status` stopped
    /// being `pending`. Nil until then, and possibly forever: iOS guarantees
    /// no delivery for the silent push.
    ///
    /// Optional rather than required so a build pointed at a server that
    /// predates the field still decodes its activity feed.
    var ackedAt: Date?
    /// Sent by the sender's scripts — one of their API tokens — rather than
    /// by the sender in person. Visible to both sides.
    ///
    /// Optional for the same reason as `ackedAt`; read it through
    /// `isAutomated`.
    var viaApiToken: Bool?
    /// The name the sender gave that token. Only ever present for the
    /// sender's own view, and gone once the token is revoked.
    var apiTokenName: String?
}

extension PokeEvent {
    /// How long the poke took to be confirmed. Nil while nothing has acked.
    var timeToAck: TimeInterval? {
        guard let ackedAt else { return nil }
        return ackedAt.timeIntervalSince(createdAt)
    }

    /// Sent by a script rather than in person. False when the server doesn't
    /// say — every poke was in person before it could.
    var isAutomated: Bool { viaApiToken ?? false }
}

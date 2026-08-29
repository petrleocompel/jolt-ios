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
}

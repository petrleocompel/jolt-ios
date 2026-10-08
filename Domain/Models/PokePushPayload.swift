import Foundation

/// The APNs payload shape for an incoming poke — see `docs/openapi.yaml`
/// `PokePushPayload` schema. Self-contained (sender name + the exact
/// stimulus to fire) so handling one never needs a round-trip API call
/// first — important for the background silent-push path, which has a
/// tight execution budget.
struct PokePushPayload: Codable, Equatable {
    var pokeID: UUID
    var senderHandle: String
    var senderDisplayName: String
    /// Who the poke is addressed to.
    ///
    /// A device is registered to exactly one account at a time, but a stale
    /// registration (signed in as someone else, signed out, token never
    /// re-registered) used to be invisible here: the push arrived, the
    /// wearable fired, and the only trace was an ack the server 404'd. With a
    /// handle to compare against, a poke meant for somebody else can be
    /// dropped instead of fired.
    ///
    /// Optional: a server that predates the field sends nothing, and an
    /// absent addressee means "can't tell", which must never be read as
    /// "not mine".
    var recipientHandle: String?
    var stimulus: StimulusConfig
    /// Sent by the sender's scripts (an API token), not in person. The alert
    /// text already says so; this is for anything the app renders itself.
    ///
    /// Optional: a server that predates it sends nothing.
    var viaApiToken: Bool?
}

extension PokePushPayload {
    /// Parses the `"poke"` object out of a raw APNs `userInfo` dictionary —
    /// see the `PokePushPayload` schema and example payload in
    /// `docs/openapi.yaml`. Used identically for a real push, a
    /// `simctl push` test payload, and a local-notification-wrapped test.
    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String, type == "poke",
              let dict = userInfo["poke"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let payload = try? JSONDecoder().decode(PokePushPayload.self, from: data) else {
            return nil
        }
        self = payload
    }
}

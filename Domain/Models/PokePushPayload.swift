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
    var stimulus: StimulusConfig
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

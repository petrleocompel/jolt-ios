import Foundation

/// The APNs payload for a *diagnostic* push — see `TestPushPayload` in the
/// server contract (jolt-server `openapi/jolt-v1.yaml`; this repo's
/// `docs/openapi.yaml` predates it). Sent by "Send test notification" here in Settings or
/// from the server's web dashboard, and deliberately not a poke: there is no
/// `PokeEvent` behind it, so it never appears in Friends activity and is
/// acked to `/devices/test-push/{testID}/ack` instead.
///
/// The server's `source` is ignored on this side, and `sentAt` only feeds the
/// alert text — the round trip is timed where it was started, so the phone
/// has nothing to add.
struct TestPushPayload: Codable, Equatable {
    var testID: UUID
    /// Which of the account's devices this copy was addressed to. Echoed back
    /// in the ack so a fan-out to several phones can be told apart.
    var deviceID: UUID
    /// Absent for a notification-only test: delivery can then be checked with
    /// no Pavlok connected at all.
    var stimulus: StimulusConfig?
    /// ISO-8601, kept as sent; see `PokePushPayload.sentAt`.
    var sentAt: String?
    /// See `PokePushPayload.serverId`.
    var serverId: String?
}

extension TestPushPayload {
    /// Parses the `"test"` object out of a raw APNs `userInfo` dictionary.
    /// Mirrors `PokePushPayload(userInfo:)`, and is checked first by the
    /// notification handlers because the two payload types are disjoint.
    init?(userInfo: [AnyHashable: Any]) {
        guard let type = userInfo["type"] as? String, type == "test",
              let dict = userInfo["test"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let payload = try? JSONDecoder().decode(TestPushPayload.self, from: data) else {
            return nil
        }
        self = payload
    }
}

/// Which iOS entry point saw a test push. Reported in the ack so the alert
/// and the silent halves of one test show up as separate confirmations —
/// they exercise genuinely different code paths, and the background one is
/// the half that tends to break.
enum TestPushPath: String, Codable {
    /// The user tapped the notification.
    case alert
    /// `didReceiveRemoteNotification` — the silent `content-available` wake.
    case background
    /// Presented while the app was already open.
    case foreground
}

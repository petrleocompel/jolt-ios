import Foundation

/// A friend on a **Pavlok** account, as returned by `/friendships/get-friends`.
///
/// Deliberately separate from `Friend` (the Jolt-server type): the two
/// backends have different ids, different permission models and different
/// capabilities, and the app keeps them in separate sections so it is never
/// ambiguous which account a poke will go through. See `docs/PAVLOK-API.md`.
struct PavlokFriend: Identifiable, Equatable, Codable {
    /// Pavlok's numeric user id — the path component of `/pokes/send/user/{id}`.
    var id: Int
    var firstName: String?
    var lastName: String?
    var username: String?
    var profilePictureURL: URL?

    var displayName: String {
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        if let username, !username.isEmpty { return username }
        return "Pavlok user \(id)"
    }
}

/// What a friend allows *me* to send them, from `/poke-permissions/received`.
///
/// Note `canChime` is Pavlok's name for beep/piezo. `maxZapValue` caps zap
/// intensity — the composer clamps to it rather than letting the server reject
/// the poke.
struct PavlokPokePermission: Equatable, Codable {
    var friendID: Int
    var canVibrate: Bool
    var canChime: Bool
    var canZap: Bool
    var maxZapValue: Int

    static let none = PavlokPokePermission(
        friendID: 0, canVibrate: false, canChime: false, canZap: false, maxZapValue: 0
    )

    func allows(_ kind: StimulusKind) -> Bool {
        switch kind {
        case .zap: return canZap
        case .vibe: return canVibrate
        case .beep: return canChime
        }
    }

    /// The highest intensity this grant permits for `kind`. Only zap is capped
    /// by the API; vibe and beep are all-or-nothing.
    func maxIntensity(for kind: StimulusKind) -> Int {
        switch kind {
        case .zap: return max(0, min(100, maxZapValue))
        case .vibe, .beep: return 100
        }
    }
}

/// One entry from `/diagnostic_logs/` — the wearable's own uploaded log.
///
/// **There is no sender.** This records that the device fired something, not
/// who caused it, so it cannot attribute a poke to a friend (see
/// `docs/PAVLOK-API.md`, "Receiving pokes"). It is surfaced as a best-effort
/// activity feed and the UI says as much.
struct PavlokStimulusLogEntry: Identifiable, Equatable, Codable {
    var id: String
    var kind: StimulusKind?
    /// The raw `name` from the API (`Zap` / `Beep` / `Vibe`), kept so an
    /// unrecognised value can still be shown rather than dropped.
    var rawName: String
    var timestamp: Date
}

/// The signed-in Pavlok account.
struct PavlokAccount: Equatable, Codable {
    var userID: Int
    var email: String
    var firstName: String?
    var lastName: String?

    var displayName: String {
        let full = [firstName, lastName].compactMap { $0 }.joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? email : full
    }
}

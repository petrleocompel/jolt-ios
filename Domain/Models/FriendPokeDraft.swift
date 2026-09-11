import Foundation

/// Last stimulus kind + intensity used in a friend's poke composer.
/// Repetitions are intentionally omitted — they stay at the composer's
/// default each visit.
struct FriendPokeDraft: Codable, Equatable {
    var kind: StimulusKind
    var intensity: Int

    /// Preferred first-open defaults when nothing has been saved yet.
    static let preferredDefault = FriendPokeDraft(kind: .vibe, intensity: 30)

    /// Resolve a draft against what this friend currently allows: pick the
    /// remembered kind when still allowed (else preferred vibe, else first
    /// allowed), and clamp intensity to that kind's cap.
    static func resolved(
        saved: FriendPokeDraft?,
        permissions: FriendPermissionSet
    ) -> FriendPokeDraft? {
        let allowed = permissions.allowedKinds
        guard !allowed.isEmpty else { return nil }

        let preferredKind: StimulusKind
        if let saved, allowed.contains(saved.kind) {
            preferredKind = saved.kind
        } else if allowed.contains(.vibe) {
            preferredKind = .vibe
        } else {
            preferredKind = allowed[0]
        }

        let cap = max(permissions[preferredKind].maxIntensity, 0)
        let rawIntensity = saved?.intensity ?? Self.preferredDefault.intensity
        let intensity = min(max(rawIntensity, 0), cap)
        return FriendPokeDraft(kind: preferredKind, intensity: intensity)
    }
}

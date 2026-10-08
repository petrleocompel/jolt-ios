import Foundation

/// One friend's poke rights for one stimulus kind. Per-stimulus rather than
/// one blanket switch — a friend might be fine to vibe you but not zap you.
struct StimulusPermission: Codable, Equatable {
    var isAllowed: Bool
    var maxIntensity: Int
    var cooldownSeconds: Int
    /// The granter's explicit answer to "may this friend's scripts (pokes
    /// sent with their API tokens) send this too?". Nil means no answer yet,
    /// which follows the server's policy (`ServerPolicies`). Only matters
    /// while `isAllowed` is true.
    ///
    /// Never sent back as part of an ordinary edit — see
    /// `StimulusPermissionUpdate` — so moving a slider can't wipe it.
    var automationAllowed: Bool?
    /// Whether automated pokes are accepted right now: `automationAllowed`,
    /// or the server's default when that is nil. Read-only.
    ///
    /// Optional like `PokeEvent.ackedAt`: a server that predates automation
    /// consent sends neither key, and nil here is how the UI tells that
    /// apart from "no answer yet" and hides the control instead of
    /// guessing.
    var automationAllowedEffective: Bool?

    static let disabled = StimulusPermission(isAllowed: false, maxIntensity: 0, cooldownSeconds: 60)

    static func allowed(maxIntensity: Int = 40, cooldownSeconds: Int = 60) -> StimulusPermission {
        StimulusPermission(isAllowed: true, maxIntensity: maxIntensity, cooldownSeconds: cooldownSeconds)
    }

    /// Whether the server reports automation consent at all.
    var supportsAutomationConsent: Bool { automationAllowedEffective != nil }

    /// Same allow / cap / cooldown, whatever either side says about
    /// automation. What a preset compares, since presets never touch it.
    func hasSameGrant(as other: StimulusPermission) -> Bool {
        isAllowed == other.isAllowed
            && maxIntensity == other.maxIntensity
            && cooldownSeconds == other.cooldownSeconds
    }

    /// This grant, carrying `other`'s automation answer instead of its own.
    /// An edit to the grant leaves the answer as it was, and vice versa.
    func keepingAutomationConsent(of other: StimulusPermission) -> StimulusPermission {
        var merged = self
        merged.automationAllowed = other.automationAllowed
        merged.automationAllowedEffective = other.automationAllowedEffective
        return merged
    }
}

/// A full permission grant, one entry per `StimulusKind`. Two of these exist
/// per friendship: what they grant you, and what you grant them — never
/// symmetric, always edited from the granter's side.
struct FriendPermissionSet: Codable, Equatable {
    var zap: StimulusPermission
    var vibe: StimulusPermission
    var beep: StimulusPermission

    static let none = FriendPermissionSet(zap: .disabled, vibe: .disabled, beep: .disabled)

    subscript(kind: StimulusKind) -> StimulusPermission {
        get {
            switch kind {
            case .zap: return zap
            case .vibe: return vibe
            case .beep: return beep
            }
        }
        set {
            switch kind {
            case .zap: zap = newValue
            case .vibe: vibe = newValue
            case .beep: beep = newValue
            }
        }
    }

    var allowedKinds: [StimulusKind] {
        StimulusKind.allCases.filter { self[$0].isAllowed }
    }
}

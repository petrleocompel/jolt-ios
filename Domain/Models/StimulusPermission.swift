import Foundation

/// One friend's poke rights for one stimulus kind. Per-stimulus rather than
/// one blanket switch — a friend might be fine to vibe you but not zap you.
struct StimulusPermission: Codable, Equatable {
    var isAllowed: Bool
    var maxIntensity: Int
    var cooldownSeconds: Int

    static let disabled = StimulusPermission(isAllowed: false, maxIntensity: 0, cooldownSeconds: 60)

    static func allowed(maxIntensity: Int = 40, cooldownSeconds: Int = 60) -> StimulusPermission {
        StimulusPermission(isAllowed: true, maxIntensity: maxIntensity, cooldownSeconds: cooldownSeconds)
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

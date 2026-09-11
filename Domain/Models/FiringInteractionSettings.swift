import Foundation

/// Per-stimulus firing gesture. Lets Zap stay behind a confirm dialog while
/// Vibe stays one-tap and Beep requires a hold — without forcing one mode
/// onto every fire-able control.
struct FiringInteractionSettings: Codable, Equatable {
    var zap: FiringInteractionMode
    var vibe: FiringInteractionMode
    var beep: FiringInteractionMode

    static let `default` = FiringInteractionSettings(zap: .tap, vibe: .tap, beep: .tap)

    static func uniform(_ mode: FiringInteractionMode) -> FiringInteractionSettings {
        FiringInteractionSettings(zap: mode, vibe: mode, beep: mode)
    }

    subscript(kind: StimulusKind) -> FiringInteractionMode {
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

    /// Short Settings-row summary: one name when every kind matches, otherwise
    /// "Mixed".
    var summaryLabel: String {
        let modes = [zap, vibe, beep]
        if let first = modes.first, modes.allSatisfy({ $0 == first }) {
            return first.displayName
        }
        return "Mixed"
    }
}

import Foundation

/// How a fire-able control (a stimulus row, quick poke, the poke composer)
/// turns a touch into an actual send. User-configurable in Settings so the
/// Remote redesign's press-and-hold doesn't force itself on everyone —
/// `.tap` reproduces the app's original one-tap behavior exactly.
enum FiringInteractionMode: String, CaseIterable, Codable, Identifiable {
    case tap
    case hold
    case confirm

    var id: String { rawValue }

    /// `.tap` — reproduces the app's original one-tap-fires behavior exactly,
    /// so upgrading users see no change until they opt into `.hold`/`.confirm`
    /// themselves.
    static let `default`: FiringInteractionMode = .tap

    var displayName: String {
        switch self {
        case .tap: return "Tap"
        case .hold: return "Hold"
        case .confirm: return "Confirm dialog"
        }
    }

    var description: String {
        switch self {
        case .tap: return "A single tap fires immediately."
        case .hold: return "Press and hold to fire — releasing early cancels it. "
            + "A high-intensity stimulus asks you to hold a second time to confirm."
        case .confirm: return "Tapping asks you to confirm before it fires."
        }
    }

    /// The verb this mode's control copy should use — "Hold to fire" vs.
    /// "Tap to fire". `.confirm` reads as a tap too; the dialog is the extra
    /// step, not the gesture.
    var actionVerb: String {
        switch self {
        case .tap, .confirm: return "Tap"
        case .hold: return "Hold"
        }
    }
}

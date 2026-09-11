import Foundation

/// Named shortcuts for poke success feedback. Selecting a profile writes the
/// matching toggle set; editing a toggle afterwards may flip the profile to
/// `.custom`.
enum PokeFeedbackProfile: String, CaseIterable, Codable, Identifiable {
    case off
    case minimal
    case standard
    case rich
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .minimal: return "Minimal"
        case .standard: return "Standard"
        case .rich: return "Rich"
        case .custom: return "Custom"
        }
    }
}

/// What happens after a poke is successfully sent — banner, flash, haptic,
/// and/or a temporary "Sent" label on the fire control.
struct PokeFeedbackSettings: Codable, Equatable {
    var profile: PokeFeedbackProfile
    var showBanner: Bool
    var flashButton: Bool
    var playHaptic: Bool
    var swapButtonLabel: Bool

    static let `default` = PokeFeedbackSettings.preset(.standard)

    static func preset(_ profile: PokeFeedbackProfile) -> PokeFeedbackSettings {
        switch profile {
        case .off:
            return PokeFeedbackSettings(
                profile: .off,
                showBanner: false,
                flashButton: false,
                playHaptic: false,
                swapButtonLabel: false
            )
        case .minimal:
            return PokeFeedbackSettings(
                profile: .minimal,
                showBanner: false,
                flashButton: true,
                playHaptic: false,
                swapButtonLabel: false
            )
        case .standard:
            return PokeFeedbackSettings(
                profile: .standard,
                showBanner: true,
                flashButton: true,
                playHaptic: true,
                swapButtonLabel: false
            )
        case .rich:
            return PokeFeedbackSettings(
                profile: .rich,
                showBanner: true,
                flashButton: true,
                playHaptic: true,
                swapButtonLabel: true
            )
        case .custom:
            return .default
        }
    }

    mutating func applyProfile(_ profile: PokeFeedbackProfile) {
        guard profile != .custom else { return }
        self = .preset(profile)
    }

    /// After a manual toggle edit, snap back to a named profile when the
    /// toggles match one exactly; otherwise mark `.custom`.
    mutating func reconcileProfile() {
        for candidate in [PokeFeedbackProfile.off, .minimal, .standard, .rich] {
            let preset = Self.preset(candidate)
            if showBanner == preset.showBanner
                && flashButton == preset.flashButton
                && playHaptic == preset.playHaptic
                && swapButtonLabel == preset.swapButtonLabel {
                profile = candidate
                return
            }
        }
        profile = .custom
    }

    var isEnabled: Bool {
        showBanner || flashButton || playHaptic || swapButtonLabel
    }
}

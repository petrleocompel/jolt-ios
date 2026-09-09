import SwiftUI

/// Shared style pieces for the Remote redesign. `AccentColor` in the asset
/// catalog is already the design's green (`#00E676`), so green reuses
/// `Color.accentColor` everywhere; violet has no existing token and is added
/// here as a fixed value — it stands for "the social/poke layer" regardless
/// of light or dark mode, the same way the design doc uses it.
enum RemoteTheme {
    static let violet = Color(red: 0.561, green: 0.482, blue: 1.0)   // #8F7BFF
    static let violetInk = Color(red: 0.788, green: 0.745, blue: 1.0) // #C9BEFF
    static let amber = Color(red: 1.0, green: 0.690, blue: 0.125)    // #FFB020

    /// The Remote dashboard/Customize/Device-detail screens stay branded
    /// black in both system appearances (per the design doc), so this is a
    /// literal color, not an adaptive one.
    static let background = Color(red: 0.039, green: 0.039, blue: 0.039) // #0A0A0A
}

extension Font {
    /// Stand-in for the design's "Space Grotesk" — no custom font is bundled
    /// in this project, and rounded system numerals read the same "friendly
    /// geometric" way without adding font assets.
    static func remoteNumeral(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// One card look per role, matching the design doc's gradients. Only used on
/// the forced-black Remote screens — `RemoteDashboardView`,
/// `RemoteCustomizeView`, `RemoteDeviceDetailView` — where a literal black
/// background is already in effect.
enum RemoteCardStyle {
    case device
    case stimulus
    case quickPoke
    case neutral

    var borderColor: Color {
        switch self {
        case .device: return Color.accentColor.opacity(0.32)
        case .stimulus, .neutral: return .white.opacity(0.13)
        case .quickPoke: return RemoteTheme.violet.opacity(0.34)
        }
    }

    @ViewBuilder
    var background: some View {
        switch self {
        case .device:
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.015)],
                startPoint: .top, endPoint: .bottom
            )
        case .stimulus, .neutral:
            LinearGradient(
                colors: [.white.opacity(0.035), .white.opacity(0.008)],
                startPoint: .top, endPoint: .bottom
            )
        case .quickPoke:
            LinearGradient(
                colors: [RemoteTheme.violet.opacity(0.12), RemoteTheme.violet.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            )
        }
    }
}

private struct RemoteCardModifier: ViewModifier {
    let style: RemoteCardStyle
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(style.background)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(style.borderColor, lineWidth: 1)
            )
    }
}

extension View {
    func remoteCard(_ style: RemoteCardStyle, cornerRadius: CGFloat = 22) -> some View {
        modifier(RemoteCardModifier(style: style, cornerRadius: cornerRadius))
    }
}

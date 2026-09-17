import SwiftUI

// Shared look of the full-screen alarm flow (ringing screen + dismiss
// challenges). These screens are always dark, like a bedside clock, so the
// colors below are literal rather than adaptive.

enum AlarmScreenStyle {
    /// The design's `#1C1C1E` card and `#2C2C2E` raised-control greys.
    static let card = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let raised = Color(red: 0.173, green: 0.173, blue: 0.180)
    static let horizontalPadding: CGFloat = 24
}

/// Full-width pill used for the primary/secondary actions at the bottom of
/// every alarm screen. `minHeight` rather than a fixed height so larger
/// Dynamic Type sizes wrap instead of clipping.
struct AlarmCapsuleButtonStyle: ButtonStyle {
    enum Role { case primary, secondary }
    let role: Role

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(role == .primary ? .semibold : .regular))
            .multilineTextAlignment(.center)
            .foregroundStyle(role == .primary ? Color.black : Color.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Capsule().fill(role == .primary ? Color.accentColor : Color.white.opacity(0.10))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// Eyebrow + large title header shared by the challenge screens.
struct AlarmChallengeHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AlarmEyebrow(text: eyebrow, color: .secondary)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AlarmEyebrow: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

extension DismissChallenge {
    /// Copy for the ringing screen's primary button.
    var ringingDismissTitle: String {
        switch self {
        case .none: return "Dismiss"
        case .mathPuzzle: return "Dismiss — solve a puzzle"
        case .jumpingJacks: return "Dismiss — do \(JumpingJacksChallengeView.target) jumping jacks"
        case .qrCodeScan: return "Dismiss — scan your code"
        }
    }

    /// Copy for "switch challenge" links and menu items.
    var switchTitle: String {
        switch self {
        case .none: return "Dismiss without a challenge"
        case .mathPuzzle: return "Use a math puzzle instead"
        case .jumpingJacks: return "Use jumping jacks instead"
        case .qrCodeScan: return "Use a QR code instead"
        }
    }
}

/// Grey "Switch challenge" capsule for the jacks and QR screens: a
/// confirmation dialog listing the other challenges this alarm allows.
struct SwitchChallengeButton: View {
    let alternatives: [DismissChallenge]
    let onSwitch: (DismissChallenge) -> Void
    @State private var isChoosing = false

    var body: some View {
        if !alternatives.isEmpty {
            Button("Switch challenge") { isChoosing = true }
                .buttonStyle(AlarmCapsuleButtonStyle(role: .secondary))
                .accessibilityIdentifier("switchChallengeButton")
                .confirmationDialog("Switch challenge", isPresented: $isChoosing, titleVisibility: .visible) {
                    ForEach(alternatives) { challenge in
                        Button(challenge.switchTitle) { onSwitch(challenge) }
                    }
                }
        }
    }
}

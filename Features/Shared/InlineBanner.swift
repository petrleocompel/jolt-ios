import SwiftUI

/// The app's one way of showing a transient message over a screen.
///
/// Before this there were three: an `alert` in onboarding and button config,
/// red `Text` inline in add-friend and diagnostics, and a bespoke capsule on
/// the remote. Alerts are the worst of the three here — they can't present
/// when another screen is pushed on top (UIKit refuses with "view is not in
/// the window hierarchy"), which silently swallowed errors, and they're
/// unusable for an action the user repeats.
struct InlineBanner: View {
    enum Style {
        case error
        case success

        var systemImage: String {
            switch self {
            case .error: return "exclamationmark.triangle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .error: return .red
            case .success: return .secondary
            }
        }
    }

    let text: String
    var style: Style = .error

    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: style.systemImage).foregroundStyle(style.tint)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // Announced, not just drawn: for an error this may be the only
        // indication the action failed.
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Shows `message` as a dismissible error banner along the bottom edge.
    func errorBanner(_ message: String?, onDismiss: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom) {
            if let message {
                InlineBanner(text: message, style: .error)
                    .onTapGesture(perform: onDismiss)
                    .accessibilityIdentifier("errorFeedback")
                    .accessibilityHint("Tap to dismiss")
            }
        }
        .animation(.snappy, value: message)
    }
}

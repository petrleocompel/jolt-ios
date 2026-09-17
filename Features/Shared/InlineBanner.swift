import SwiftUI

/// The app's one way of showing a transient message over a screen.
///
/// Before this there were three: an `alert` in onboarding and button config,
/// red `Text` inline in add-friend and diagnostics, and a bespoke capsule on
/// the remote. Alerts are the worst of the three here — they can't present
/// when another screen is pushed on top (UIKit refuses with "view is not in
/// the window hierarchy"), which silently swallowed errors, and they're
/// unusable for an action the user repeats.
///
/// Pinned to the bottom edge (a safe-area inset) rather than the top, where
/// the design draws it: an inset never moves content under a finger that is
/// about to tap Fire again, it stays visible inside sheets, and it sits next
/// to the controls that produced it. The look — tinted card, thin border,
/// × — is the design's.
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
            case .success: return .accentColor
            }
        }
    }

    let text: String
    var style: Style = .error
    /// Shows a × when set. Errors stay until dismissed; success messages
    /// clear themselves, so callers usually leave this `nil` for them.
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: style.systemImage)
                .foregroundStyle(style.tint)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(style.tint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(style.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style.tint.opacity(0.5), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        // Announced, not just drawn: for an error this may be the only
        // indication the action failed.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension View {
    /// Shows `message` as a dismissible error banner along the bottom edge.
    func errorBanner(_ message: String?, onDismiss: @escaping () -> Void) -> some View {
        safeAreaInset(edge: .bottom) {
            if let message {
                InlineBanner(text: message, style: .error, onDismiss: onDismiss)
                    .accessibilityIdentifier("errorFeedback")
            }
        }
        .animation(.snappy, value: message)
    }
}

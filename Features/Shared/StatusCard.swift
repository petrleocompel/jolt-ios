import SwiftUI

/// A tinted card that *replaces* a control while something needs the user's
/// attention: a poke that failed, a friend who's gone, a read that didn't
/// come back. Unlike `InlineBanner` it carries its own way forward (Retry,
/// Close), so it lives where the control was instead of floating over the
/// screen.
struct StatusCard<Actions: View>: View {
    let tint: Color
    let eyebrow: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(tint)
            Text(message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 8)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.5))
        )
    }
}

/// The capsule buttons inside a `StatusCard`. Neutral unless given a fill.
struct StatusCardButton: View {
    let title: String
    var fill: Color?
    var ink: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(fill == nil ? .body : .body.weight(.semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(fill ?? Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }
}

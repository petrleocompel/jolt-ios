import Observation
import SwiftUI

/// Drives one press-and-hold's progress, independent of any particular
/// control's visuals. One instance per fire-able control, held as `@State`.
@MainActor
@Observable
final class HoldFireGesture {
    private(set) var progress: Double = 0
    private(set) var isHolding = false

    @ObservationIgnored
    private var task: Task<Void, Never>?

    /// Mirrors the design doc's `ramp()` — ticks roughly every frame so the
    /// fill animates smoothly, and calls `onComplete` the instant the hold
    /// reaches `durationSeconds`.
    func begin(durationSeconds: Double, onComplete: @escaping () -> Void) {
        guard !isHolding else { return }
        task?.cancel()
        isHolding = true
        progress = 0
        let start = Date()
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(start)
                let ratio = min(1, elapsed / durationSeconds)
                self.progress = ratio
                if ratio >= 1 {
                    self.isHolding = false
                    onComplete()
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isHolding = false
        progress = 0
    }
}

enum FireControlState {
    case idle
    case holding(progress: Double)

    var isHolding: Bool {
        if case .holding = self { return true }
        return false
    }

    var progress: Double {
        if case .holding(let progress) = self { return progress }
        return 0
    }
}

/// The one place `FiringInteractionMode` becomes an actual gesture. Every
/// fire-able control in the Remote redesign — stimulus rows, quick poke,
/// the poke composer — wraps its own visuals in this rather than
/// implementing tap/hold/confirm three separate times.
struct FireControl<Label: View>: View {
    /// Above this, `.hold` mode gates behind a second confirmation hold.
    /// Also used by callers to badge a stimulus "HIGH" before it's even
    /// pressed, so the two stay in sync.
    static var defaultHighIntensityThreshold: Int { 60 }

    var mode: FiringInteractionMode
    var isEnabled: Bool = true
    var holdDuration: Double = 0.85
    var confirmTitle: String
    var confirmMessage: String?
    /// When both this and a percent above `highIntensityThreshold` are set,
    /// `.hold` mode routes the press through a second confirmation hold in a
    /// sheet instead of firing directly off the first one — the design's
    /// safety gate for anything above a comfort threshold. Rows that don't
    /// pass this (quick poke, the composer) never gate.
    var highIntensityPercent: Int?
    var highIntensityThreshold: Int = Self.defaultHighIntensityThreshold
    var onFire: () -> Void
    @ViewBuilder var label: (FireControlState) -> Label

    @State private var hold = HoldFireGesture()
    @State private var isConfirmingTap = false
    @State private var isShowingHighIntensitySheet = false

    private var isAboveThreshold: Bool {
        guard let highIntensityPercent else { return false }
        return highIntensityPercent > highIntensityThreshold
    }

    var body: some View {
        Group {
            switch mode {
            case .tap:
                Button(action: fireIfEnabled) { label(.idle) }
                    .buttonStyle(.plain)

            case .confirm:
                Button { isConfirmingTap = true } label: { label(.idle) }
                    .buttonStyle(.plain)
                    .confirmationDialog(confirmTitle, isPresented: $isConfirmingTap, titleVisibility: .visible) {
                        Button("Send") { fireIfEnabled() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        if let confirmMessage { Text(confirmMessage) }
                    }

            case .hold:
                label(hold.isHolding ? .holding(progress: hold.progress) : .idle)
                    .contentShape(.rect)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in beginHoldIfNeeded() }
                            .onEnded { _ in hold.cancel() }
                    )
                    .sheet(isPresented: $isShowingHighIntensitySheet) {
                        HighIntensityConfirmSheet(
                            title: confirmTitle,
                            message: confirmMessage,
                            holdDuration: holdDuration,
                            onFire: {
                                isShowingHighIntensitySheet = false
                                onFire()
                            }
                        )
                    }
            }
        }
        .disabled(!isEnabled)
    }

    private func fireIfEnabled() {
        guard isEnabled else { return }
        onFire()
    }

    private func beginHoldIfNeeded() {
        guard isEnabled, !hold.isHolding else { return }
        if isAboveThreshold {
            isShowingHighIntensitySheet = true
            return
        }
        hold.begin(durationSeconds: holdDuration, onComplete: onFire)
    }
}

/// A press-and-hold bar that fills left-to-right as progress advances —
/// shared by the high-intensity sheet, quick poke, and the poke composer.
struct HoldFillBar: View {
    var isHolding: Bool
    var progress: Double
    var idleLabel: String
    var holdingLabel: String
    var tint: Color
    var ink: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 17, style: .continuous).fill(tint)
                if isHolding {
                    Rectangle()
                        .fill(.white.opacity(0.22))
                        .frame(width: geometry.size.width * progress)
                        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                Text(isHolding ? holdingLabel : idleLabel)
                    .font(.remoteNumeral(16))
                    .foregroundStyle(ink)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56)
    }
}

private struct HighIntensityConfirmSheet: View {
    let title: String
    let message: String?
    let holdDuration: Double
    let onFire: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hold = HoldFireGesture()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(.white.opacity(0.22)).frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("HIGH INTENSITY")
                    .font(.caption.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(RemoteTheme.amber)
                Text(title)
                    .font(.remoteNumeral(24))
                    .foregroundStyle(.white)
                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.56))
                }
            }

            HoldFillBar(
                isHolding: hold.isHolding,
                progress: hold.progress,
                idleLabel: "Hold to fire",
                holdingLabel: "Keep holding…",
                tint: Color.accentColor,
                ink: .black
            )
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in hold.begin(durationSeconds: holdDuration, onComplete: onFire) }
                    .onEnded { _ in hold.cancel() }
            )

            Button("Cancel") {
                hold.cancel()
                dismiss()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(20)
        .padding(.bottom, 12)
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

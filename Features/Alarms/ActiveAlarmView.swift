import SwiftUI

/// Presented full-screen when a phone-alarm notification fires or is
/// tapped. Starts on a "ringing" screen (dismiss or snooze); dismissing
/// routes through the alarm's `DismissChallenge`, which the user may swap
/// for another one from the challenge screen.
///
/// Always dark: it's a bedside screen, and the full-screen cover is its own
/// presentation, so forcing the color scheme here doesn't leak into the app.
struct ActiveAlarmView: View {
    let alarmID: UUID
    let onDismiss: () -> Void

    @Environment(AppDependencies.self) private var dependencies
    @State private var loadState: LoadState = .loading
    /// `nil` while on the ringing screen; otherwise the challenge being shown.
    @State private var activeChallenge: DismissChallenge?
    @State private var snoozeError: String?

    private enum LoadState {
        case loading
        case loaded(Alarm)
        /// The alarm was deleted after its notification was scheduled (or
        /// the store failed). Still show a way out rather than a spinner.
        case missing
    }

    var body: some View {
        ZStack {
            RemoteTheme.background.ignoresSafeArea()
            content
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task { await loadAlarm() }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView()
        case .missing:
            VStack(spacing: 24) {
                Text("Alarm")
                    .font(.title2.bold())
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(AlarmCapsuleButtonStyle(role: .primary))
                    .accessibilityIdentifier("dismissAlarmButton")
            }
            .padding(.horizontal, AlarmScreenStyle.horizontalPadding)
        case .loaded(let alarm):
            if let activeChallenge {
                challengeView(activeChallenge, for: alarm)
                    .transition(.opacity)
            } else {
                RingingAlarmView(
                    alarm: alarm,
                    snoozeError: snoozeError,
                    onDismiss: { startDismiss(alarm) },
                    onSnooze: { Task { await snooze(alarm) } }
                )
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func challengeView(_ challenge: DismissChallenge, for alarm: Alarm) -> some View {
        let alternatives = Self.switchableChallenges(for: alarm, current: challenge)
        switch challenge {
        case .none:
            // Never set as `activeChallenge` (see `startDismiss`), but keep
            // the switch exhaustive without a dead-end screen.
            Color.clear.onAppear(perform: onDismiss)
        case .mathPuzzle:
            MathPuzzleChallengeView(alternatives: alternatives, onSwitch: switchTo, onSolved: onDismiss)
        case .jumpingJacks:
            JumpingJacksChallengeView(alternatives: alternatives, onSwitch: switchTo, onSolved: onDismiss)
        case .qrCodeScan:
            QRCodeChallengeView(alarm: alarm, alternatives: alternatives, onSwitch: switchTo, onSolved: onDismiss)
        }
    }

    /// Challenges the user may swap to. QR is only offered when it would
    /// actually cost something: a saved code, or the alarm's own challenge
    /// being QR already (legacy accept-any alarms). Otherwise switching to
    /// "scan any QR code" would be an easy way out of a harder challenge.
    static func switchableChallenges(for alarm: Alarm, current: DismissChallenge) -> [DismissChallenge] {
        [DismissChallenge.mathPuzzle, .jumpingJacks, .qrCodeScan].filter { candidate in
            guard candidate != current else { return false }
            if candidate == .qrCodeScan {
                return alarm.dismissQRCode != nil || alarm.dismissChallenge == .qrCodeScan
            }
            return true
        }
    }

    private func switchTo(_ challenge: DismissChallenge) {
        withAnimation { activeChallenge = challenge }
    }

    private func startDismiss(_ alarm: Alarm) {
        if alarm.dismissChallenge == .none {
            onDismiss()
        } else {
            withAnimation { activeChallenge = alarm.dismissChallenge }
        }
    }

    private func snooze(_ alarm: Alarm) async {
        do {
            try await dependencies.phoneAlarmScheduler.snooze(alarm)
            onDismiss()
        } catch {
            snoozeError = "Couldn't snooze: \(error.localizedDescription)"
        }
    }

    private func loadAlarm() async {
        guard case .loading = loadState else { return }
        let alarms = (try? await dependencies.alarmRepository.fetchAll()) ?? []
        if let alarm = alarms.first(where: { $0.id == alarmID }) {
            loadState = .loaded(alarm)
        } else {
            loadState = .missing
        }
    }
}

/// First step of every alarm: what's ringing, and dismiss vs. snooze.
private struct RingingAlarmView: View {
    let alarm: Alarm
    let snoozeError: String?
    let onDismiss: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            AlarmEyebrow(
                text: "Alarm · \(alarm.stimulus.kind.displayName) \(alarm.stimulus.intensity)%",
                color: .accentColor
            )

            Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                .font(.remoteNumeral(80))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.top, 12)
                .accessibilityIdentifier("ringingAlarmTime")

            Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            Image(systemName: "bolt.fill")
                .font(.system(size: 46))
                .foregroundStyle(Color.accentColor)
                .frame(width: 120, height: 120)
                .background(Circle().fill(Color.accentColor.opacity(0.10)))
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1.5))
                .padding(.top, 36)
                .accessibilityHidden(true)

            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Spacer(minLength: 24)

            if let snoozeError {
                Text(snoozeError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 12)
            }

            VStack(spacing: 12) {
                Button(alarm.dismissChallenge.ringingDismissTitle, action: onDismiss)
                    .buttonStyle(AlarmCapsuleButtonStyle(role: .primary))
                    .accessibilityIdentifier("dismissAlarmButton")
                Button("Snooze \(Int(PhoneAlarmScheduler.snoozeInterval / 60)) min", action: onSnooze)
                    .buttonStyle(AlarmCapsuleButtonStyle(role: .secondary))
                    .accessibilityIdentifier("snoozeAlarmButton")
            }
        }
        .padding(.horizontal, AlarmScreenStyle.horizontalPadding)
        .padding(.bottom, 24)
    }

    /// Phone alarms are a single local notification: iOS plays its sound
    /// once and nothing re-fires until the user snoozes — no repeat loop,
    /// and no stimulus sent to the wearable. The copy says exactly that
    /// rather than the design's "firing every 30 seconds".
    private var explanation: String {
        let snoozeMinutes = Int(PhoneAlarmScheduler.snoozeInterval / 60)
        if alarm.dismissChallenge == .none {
            return "This alarm rang once. Snooze to ring again in \(snoozeMinutes) minutes."
        }
        return "This alarm rang once. Finish the challenge to dismiss it, or snooze to ring again in \(snoozeMinutes) minutes."
    }
}

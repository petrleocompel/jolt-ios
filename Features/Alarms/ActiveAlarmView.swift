import SwiftUI

/// Presented full-screen when a phone-alarm notification fires or is
/// tapped. Looks up the alarm's `DismissChallenge` and routes to the
/// matching wake-up-guarantee screen; `.none` just shows a dismiss button.
struct ActiveAlarmView: View {
    let alarmID: UUID
    let onDismiss: () -> Void

    @Environment(AppDependencies.self) private var dependencies
    @State private var alarm: Alarm?

    var body: some View {
        Group {
            if let alarm {
                switch alarm.dismissChallenge {
                case .none:
                    simpleDismiss(alarm)
                case .mathPuzzle:
                    MathPuzzleChallengeView(onSolved: onDismiss)
                case .jumpingJacks:
                    JumpingJacksChallengeView(onSolved: onDismiss)
                case .qrCodeScan:
                    QRCodeChallengeView(onSolved: onDismiss)
                }
            } else {
                ProgressView().task { await loadAlarm() }
            }
        }
        .interactiveDismissDisabled()
    }

    private func simpleDismiss(_ alarm: Alarm) -> some View {
        VStack(spacing: 24) {
            Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                .font(.system(size: 64, weight: .bold, design: .rounded))
            Text(alarm.label.isEmpty ? "Alarm" : alarm.label)
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("dismissAlarmButton")
        }
    }

    private func loadAlarm() async {
        guard let alarms = try? await dependencies.alarmRepository.fetchAll() else { return }
        alarm = alarms.first { $0.id == alarmID }
    }
}

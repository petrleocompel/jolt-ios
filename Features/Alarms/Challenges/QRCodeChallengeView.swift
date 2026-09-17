import SwiftUI

/// Scan a QR code to dismiss. When the alarm has a code saved (scanned in
/// `AlarmEditView`), only that code works — the point is to force a walk to
/// wherever the user put it. Alarms saved before codes existed have none and
/// accept any code, so upgrading never leaves an alarm undismissable.
struct QRCodeChallengeView: View {
    let alarm: Alarm
    let alternatives: [DismissChallenge]
    let onSwitch: (DismissChallenge) -> Void
    let onSolved: () -> Void

    @State private var wasWrongCode = false
    /// `QRScannerView` stops its capture session after the first code it
    /// sees. Bumping this rebuilds the scanner so a wrong code can be
    /// followed by another attempt.
    @State private var scannerGeneration = 0
    /// Resume delay after a wrong code — rebuilding immediately would just
    /// re-read the same wrong code and flicker the preview.
    private let retryDelay: Duration = .seconds(1.5)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AlarmChallengeHeader(eyebrow: "QR challenge", title: "Scan your saved code")

            ZStack {
                QRScannerView(onCodeScanned: handleScan)
                    .id(scannerGeneration)
                    .accessibilityHidden(true)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(60)
                    .accessibilityHidden(true)
            }
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color(red: 0.078, green: 0.078, blue: 0.086))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .accessibilityElement()
            .accessibilityLabel("Camera viewfinder")
            .padding(.top, 30)

            if wasWrongCode {
                Text("That's not the code saved for this alarm.")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
                    .accessibilityIdentifier("qrCodeChallengeError")
            }

            Text(alarm.dismissQRCode == nil
                 ? "No code was saved for this alarm, so any QR code will dismiss it. Save one in the alarm's settings."
                 : "Only the code you saved when you set the alarm will dismiss it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            Spacer(minLength: 24)

            SwitchChallengeButton(alternatives: alternatives, onSwitch: onSwitch)
        }
        .padding(.horizontal, AlarmScreenStyle.horizontalPadding)
        .padding(.top, 32)
        .padding(.bottom, 24)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qrCodeChallengeScreen")
    }

    private func handleScan(_ code: String) {
        if alarm.acceptsDismissCode(code) {
            onSolved()
            return
        }
        wasWrongCode = true
        UIAccessibility.post(notification: .announcement, argument: "That's not the code saved for this alarm.")
        Task { @MainActor in
            try? await Task.sleep(for: retryDelay)
            scannerGeneration += 1
        }
    }
}

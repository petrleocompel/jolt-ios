import SwiftUI

/// Scan any QR code to dismiss. The Android app anchors this to a specific
/// code the user prints and places somewhere inconvenient (e.g. the
/// bathroom); v1 accepts any code — printing a specific target code is a
/// follow-up, not a protocol-recovery blocker.
struct QRCodeChallengeView: View {
    let onSolved: () -> Void

    var body: some View {
        ZStack {
            QRScannerView(onCodeScanned: { _ in onSolved() })
                .ignoresSafeArea()

            VStack {
                Text("Scan a QR code to dismiss")
                    .font(.headline)
                    .padding()
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 48)
                Spacer()
            }
        }
        .accessibilityIdentifier("qrCodeChallengeScreen")
    }
}

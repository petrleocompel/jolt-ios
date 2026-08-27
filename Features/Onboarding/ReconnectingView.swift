import SwiftUI

/// Shown on launch (or after Bluetooth power-cycles) while
/// `CompositeDeviceRepository` is trying to reconnect to the last-paired
/// device automatically, before falling back to onboarding.
struct ReconnectingView: View {
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Reconnecting to your Pavlok…")
                .font(.headline)
            Button("Cancel and pair a different device", action: onCancel)
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cancelReconnectButton")
        }
        .padding()
    }
}

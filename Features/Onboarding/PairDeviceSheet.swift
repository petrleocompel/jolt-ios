import SwiftUI

/// Pairing reached *after* onboarding — from Settings → Device or the Remote
/// tab's device card. Presented as a sheet rather than replacing the app's
/// UI, so someone who is mid-conversation on the Friends tab doesn't lose
/// their place to go connect a wearable.
///
/// Dismisses itself as soon as a device connects; until then "Not now" backs
/// out and leaves the app exactly as it was.
struct PairDeviceSheet: View {
    let viewModel: DeviceControlViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DeviceScannerList(viewModel: viewModel)
                .padding(.horizontal)
                .padding(.bottom, 16)
                .navigationTitle("Pair device")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not now") { dismiss() }
                    }
                }
                .errorBanner(viewModel.lastError) { viewModel.lastError = nil }
                .accessibilityIdentifier("pairDeviceSheet")
                .onChange(of: viewModel.connectedDevice?.id) { _, connectedID in
                    if connectedID != nil { dismiss() }
                }
        }
    }
}

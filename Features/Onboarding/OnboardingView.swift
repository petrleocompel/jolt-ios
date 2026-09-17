import SwiftUI

/// First run only: offers to pair a wearable, and — just as prominently —
/// to carry on without one. Everything that doesn't touch your own skin
/// (Friends, sending and receiving pokes, phone alarms, stimulus defaults)
/// works with no device, so this is an offer rather than a gate. Taking the
/// "not now" route records `DevicePairing.didChooseNoDeviceKey` and drops
/// straight into the app; Settings → Device and the Remote tab's device card
/// both lead back here.
struct OnboardingView: View {
    let viewModel: DeviceControlViewModel
    let onContinueWithoutDevice: () -> Void

    var body: some View {
        NavigationStack {
            DeviceScannerList(viewModel: viewModel) {
                VStack(spacing: 4) {
                    Button("Continue without a device", action: onContinueWithoutDevice)
                        .accessibilityIdentifier("continueWithoutDeviceButton")
                    Text("You can still poke friends and set phone alarms. Pair any time from Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("Pair device")
            .errorBanner(viewModel.lastError) { viewModel.lastError = nil }
        }
    }
}

import SwiftUI

/// First run only: offers to pair a wearable, and — just as prominently —
/// to carry on without one. Everything that doesn't touch your own skin
/// (Friends, sending and receiving pokes, phone alarms, stimulus defaults)
/// works with no device, so this is an offer rather than a gate. Taking the
/// "not now" route records `DevicePairing.didChooseNoDeviceKey` and drops
/// straight into the app; Settings → Device and the Remote tab's device card
/// both lead back to the same pairing sheet.
struct OnboardingView: View {
    let viewModel: DeviceControlViewModel
    let onContinueWithoutDevice: () -> Void

    @State private var isShowingPairSheet = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.accentColor)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.black)
                }
                .frame(width: 96, height: 96)
                .padding(.bottom, 14)
                .accessibilityHidden(true)

                Text("Find your Pavlok")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Pair now to fire from your phone, or carry on without one — alarms, friends and pokes work either way.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    isShowingPairSheet = true
                } label: {
                    Text("Pair a device")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Capsule().fill(Color.accentColor))
                }
                .accessibilityIdentifier("pairDeviceButton")

                Button(action: onContinueWithoutDevice) {
                    Text("Continue without a device")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Capsule().fill(Color(.tertiarySystemFill)))
                }
                .accessibilityIdentifier("continueWithoutDeviceButton")
            }
            .buttonStyle(.plain)
            .padding(.bottom, 28)
        }
        .padding(.horizontal)
        .sheet(isPresented: $isShowingPairSheet) {
            PairDeviceSheet(viewModel: viewModel)
        }
    }
}

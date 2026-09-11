import SwiftUI

/// Profile shortcuts plus individual toggles for poke success feedback.
struct PokeFeedbackSettingsView: View {
    @Bindable var service: PokeFeedbackService

    var body: some View {
        List {
            Section {
                Picker("Profile", selection: Binding(
                    get: { service.settings.profile },
                    set: { profile in
                        if profile == .custom { return }
                        service.applyProfile(profile)
                    }
                )) {
                    ForEach(PokeFeedbackProfile.allCases.filter { $0 != .custom }) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                    if service.settings.profile == .custom {
                        Text(PokeFeedbackProfile.custom.displayName).tag(PokeFeedbackProfile.custom)
                    }
                }
                .accessibilityIdentifier("pokeFeedbackProfilePicker")
            } footer: {
                Text("Profiles set the toggles below. Changing a toggle switches the profile to Custom.")
            }

            Section {
                Toggle("Banner", isOn: Binding(
                    get: { service.settings.showBanner },
                    set: { service.setShowBanner($0) }
                ))
                .accessibilityIdentifier("pokeFeedbackBannerToggle")
                Toggle("Flash button", isOn: Binding(
                    get: { service.settings.flashButton },
                    set: { service.setFlashButton($0) }
                ))
                .accessibilityIdentifier("pokeFeedbackFlashToggle")
                Toggle("Haptic", isOn: Binding(
                    get: { service.settings.playHaptic },
                    set: { service.setPlayHaptic($0) }
                ))
                .accessibilityIdentifier("pokeFeedbackHapticToggle")
                Toggle("\"Sent\" on button", isOn: Binding(
                    get: { service.settings.swapButtonLabel },
                    set: { service.setSwapButtonLabel($0) }
                ))
                .accessibilityIdentifier("pokeFeedbackLabelToggle")
            } header: {
                Text("Effects")
            } footer: {
                Text("Applies after a successful poke from Quick Poke and Friends, "
                    + "whether you fire with tap, hold, or confirm.")
            }
        }
        .navigationTitle("Poke feedback")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pokeFeedbackSettingsScreen")
    }
}

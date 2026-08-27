import SwiftUI

struct SettingsView: View {
    let deviceControlViewModel: DeviceControlViewModel
    @AppStorage(PokeSettings.doNotDisturbKey) private var pokesDoNotDisturb = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Do not disturb incoming pokes", isOn: $pokesDoNotDisturb)
                } footer: {
                    Text("While on, incoming pokes are logged in Friends activity but never fire on your device.")
                }
                Section {
                    LabeledContent("Connected", value: deviceControlViewModel.connectedDevice?.name ?? "None")
                    Button("Disconnect") {
                        deviceControlViewModel.disconnect()
                    }
                    Button("Forget device", role: .destructive) {
                        deviceControlViewModel.forgetPairedDevice()
                    }
                } header: {
                    Text("Device")
                } footer: {
                    Text("Disconnect keeps this device paired — the app reconnects to it automatically next time. "
                        + "Forget removes the pairing entirely.")
                }
                Section {
                    NavigationLink("About") { AboutView() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

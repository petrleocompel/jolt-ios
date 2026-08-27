import SwiftUI

struct SettingsView: View {
    let deviceControlViewModel: DeviceControlViewModel

    var body: some View {
        NavigationStack {
            List {
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

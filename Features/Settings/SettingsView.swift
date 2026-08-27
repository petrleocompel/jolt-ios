import SwiftUI

struct SettingsView: View {
    let deviceControlViewModel: DeviceControlViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("Device") {
                    LabeledContent("Connected", value: deviceControlViewModel.connectedDevice?.name ?? "None")
                    Button("Disconnect", role: .destructive) {
                        deviceControlViewModel.disconnect()
                    }
                }
                Section {
                    NavigationLink("About") { AboutView() }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

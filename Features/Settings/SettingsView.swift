import SwiftUI

struct SettingsView: View {
    let deviceControlViewModel: DeviceControlViewModel
    @AppStorage(PokeSettings.doNotDisturbKey) private var pokesDoNotDisturb = false
    @Environment(AppDependencies.self) private var dependencies

    /// Host only — the full base URL with `/api/v1` is too long for a row.
    private var serverSummary: String {
        ServerSettingsStore().load().baseURL.host() ?? "Not set"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Do not disturb incoming pokes", isOn: $pokesDoNotDisturb)
                } footer: {
                    Text("While on, incoming pokes are logged in Friends activity but never fire on your device.")
                }
                Section {
                    NavigationLink {
                        PokeTriggerSettingsView(
                            service: dependencies.pokeTriggerService,
                            friendsRepository: dependencies.friendsRepository
                        )
                    } label: {
                        LabeledContent(
                            "Poke from your Pavlok",
                            value: dependencies.pokeTriggerService.trigger.isArmed ? "On" : "Off"
                        )
                    }
                    .accessibilityIdentifier("pokeTriggerSettingsLink")
                } footer: {
                    Text("Press a button on your Pavlok to send a friend a poke — no firmware change, "
                        + "just your phone reacting to what the device already reports.")
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
                    NavigationLink {
                        ServerSettingsView()
                    } label: {
                        LabeledContent("Server", value: serverSummary)
                    }
                    .accessibilityIdentifier("serverSettingsLink")
                } header: {
                    Text("Account")
                } footer: {
                    Text("Friends and pokes run through a Jolt server. Point the app at your own if you host one.")
                }

                Section {
                    NavigationLink("About") { AboutView() }
                }
            }
            .navigationTitle("Settings")
            .alert("Restart Jolt to finish switching", isPresented: Bindable(dependencies).pendingServerRestartNotice) {
                Button("OK") { dependencies.pendingServerRestartNotice = false }
            } message: {
                Text("The new server is saved. Close and reopen the app to sign in against it.")
            }
        }
    }
}

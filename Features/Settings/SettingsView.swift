import SwiftUI

struct SettingsView: View {
    let deviceControlViewModel: DeviceControlViewModel
    @AppStorage(PokeSettings.doNotDisturbKey) private var pokesDoNotDisturb = false
    @Environment(AppDependencies.self) private var dependencies
    /// Owned here rather than in `AppDependencies`: the Pavlok account is an
    /// optional side-channel that only this screen and its children use, and
    /// nothing else in the app should depend on it existing.
    @State private var pavlokViewModel = PavlokAccountViewModel()

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
                        NotificationTestView(
                            viewModel: NotificationTestViewModel(repository: dependencies.pushDiagnostics)
                        )
                    } label: {
                        Text("Notifications")
                    }
                    .accessibilityIdentifier("notificationTestLink")
                } footer: {
                    Text("Check that a poke sent from the server actually reaches this phone — "
                        + "without needing a friend to send one.")
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
                    Picker("Firing", selection: Binding(
                        get: { dependencies.firingModeService.mode },
                        set: { dependencies.firingModeService.setMode($0) }
                    )) {
                        ForEach(FiringInteractionMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .accessibilityIdentifier("firingModePicker")
                } footer: {
                    Text(dependencies.firingModeService.mode.description)
                }
                Section {
                    NavigationLink {
                        QuickPokeSettingsView(
                            service: dependencies.quickPokeService,
                            friendsRepository: dependencies.friendsRepository
                        )
                    } label: {
                        LabeledContent(
                            "Quick poke",
                            value: dependencies.quickPokeService.settings.isConfigured ? "On" : "Off"
                        )
                    }
                    .accessibilityIdentifier("quickPokeSettingsLink")
                } footer: {
                    Text("Adds a one-tap poke button for a friend you choose to the Remote tab.")
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
                        PavlokAccountView(viewModel: pavlokViewModel)
                    } label: {
                        LabeledContent(
                            "Pavlok account",
                            value: pavlokViewModel.account?.displayName ?? "Not signed in"
                        )
                    }
                    .accessibilityIdentifier("pavlokAccountLink")
                } header: {
                    Text("Pavlok")
                } footer: {
                    Text("Optional. Sign in with a Pavlok account to poke your Pavlok friends "
                        + "from Jolt. Incoming Pavlok pokes can't be shown here — Pavlok "
                        + "delivers those only to their own app.")
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

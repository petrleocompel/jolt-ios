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
                deviceSection
                pokesSection
                notificationsSection
                accountSection
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
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

    private var deviceSection: some View {
        Section {
            LabeledContent {
                Text(deviceControlViewModel.connectedDevice?.name ?? "None")
            } label: {
                Label("Connected", systemImage: "antenna.radiowaves.left.and.right")
            }
            Button {
                deviceControlViewModel.disconnect()
            } label: {
                Label("Disconnect", systemImage: "xmark.circle")
            }
            Button(role: .destructive) {
                deviceControlViewModel.forgetPairedDevice()
            } label: {
                Label("Forget device", systemImage: "trash")
            }
        } header: {
            Text("Device")
        } footer: {
            Text("Disconnect keeps this device paired — the app reconnects to it automatically next time. "
                + "Forget removes the pairing entirely.")
        }
    }

    private var pokesSection: some View {
        Section {
            Toggle(isOn: $pokesDoNotDisturb) {
                Label("Do not disturb incoming pokes", systemImage: "moon.zzz.fill")
            }
            NavigationLink {
                PokeTriggerSettingsView(
                    service: dependencies.pokeTriggerService,
                    friendsRepository: dependencies.friendsRepository
                )
            } label: {
                LabeledContent {
                    Text(dependencies.pokeTriggerService.trigger.isArmed ? "On" : "Off")
                } label: {
                    Label("Poke from your Pavlok", systemImage: "hand.tap.fill")
                }
            }
            .accessibilityIdentifier("pokeTriggerSettingsLink")
            NavigationLink {
                QuickPokeSettingsView(
                    service: dependencies.quickPokeService,
                    friendsRepository: dependencies.friendsRepository
                )
            } label: {
                LabeledContent {
                    Text(dependencies.quickPokeService.settings.isConfigured ? "On" : "Off")
                } label: {
                    Label("Quick poke", systemImage: "bolt.fill")
                }
            }
            .accessibilityIdentifier("quickPokeSettingsLink")
            Picker(selection: Binding(
                get: { dependencies.firingModeService.mode },
                set: { dependencies.firingModeService.setMode($0) }
            )) {
                ForEach(FiringInteractionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            } label: {
                Label("Firing", systemImage: "slider.horizontal.3")
            }
            .accessibilityIdentifier("firingModePicker")
        } header: {
            Text("Pokes & Firing")
        } footer: {
            Text("While Do Not Disturb is on, incoming pokes are logged in Friends activity but "
                + "never fire your device. " + dependencies.firingModeService.mode.description)
        }
    }

    private var notificationsSection: some View {
        Section {
            NavigationLink {
                NotificationTestView(
                    viewModel: NotificationTestViewModel(repository: dependencies.pushDiagnostics)
                )
            } label: {
                Label("Notifications", systemImage: "bell.badge")
            }
            .accessibilityIdentifier("notificationTestLink")
        } footer: {
            Text("Check that a poke sent from the server actually reaches this phone — "
                + "without needing a friend to send one.")
        }
    }

    private var accountSection: some View {
        Section {
            NavigationLink {
                PavlokAccountView(viewModel: pavlokViewModel)
            } label: {
                LabeledContent {
                    Text(pavlokViewModel.account?.displayName ?? "Not signed in")
                } label: {
                    Label("Pavlok account", systemImage: "person.crop.circle.badge.checkmark")
                }
            }
            .accessibilityIdentifier("pavlokAccountLink")
            NavigationLink {
                ServerSettingsView()
            } label: {
                LabeledContent {
                    Text(serverSummary)
                } label: {
                    Label("Server", systemImage: "server.rack")
                }
            }
            .accessibilityIdentifier("serverSettingsLink")
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in with a Pavlok account to poke your Pavlok friends from Jolt — optional, "
                + "and separate from the Jolt server that runs Friends and pokes here.")
        }
    }
}

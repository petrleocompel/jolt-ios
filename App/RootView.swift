import SwiftUI

struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var deviceControlViewModel: DeviceControlViewModel?
    /// Set by "Continue without a device" on the first-run pairing screen.
    /// See `DevicePairing` for why pairing is an offer rather than a gate.
    @AppStorage(DevicePairing.didChooseNoDeviceKey) private var didChooseNoDevice = false

    var body: some View {
        Group {
            if let viewModel = deviceControlViewModel {
                if showsPairingOffer(for: viewModel) {
                    OnboardingView(viewModel: viewModel) { didChooseNoDevice = true }
                } else {
                    MainTabView(deviceControlViewModel: viewModel)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if deviceControlViewModel == nil {
                deviceControlViewModel = DeviceControlViewModel(repository: dependencies.deviceRepository)
            }
        }
        .fullScreenCover(isPresented: activeAlarmBinding) {
            if let alarmID = dependencies.notificationDelegate.activeAlarmID {
                ActiveAlarmView(alarmID: alarmID) {
                    dependencies.notificationDelegate.clearActiveAlarm()
                }
            }
        }
    }

    /// Only a user who has neither paired a device nor declined to is shown
    /// the pairing screen. In particular a *paired but unreachable* device
    /// (out of range, Bluetooth off, mid-reconnect) goes straight to the tabs
    /// — reconnect progress shows non-blockingly on the Remote tab's device
    /// card, so losing the wearable never costs you the rest of the app.
    private func showsPairingOffer(for viewModel: DeviceControlViewModel) -> Bool {
        viewModel.connectedDevice == nil && !viewModel.hasPairedDevice && !didChooseNoDevice
    }

    private var activeAlarmBinding: Binding<Bool> {
        Binding(
            get: { dependencies.notificationDelegate.activeAlarmID != nil },
            set: { if !$0 { dependencies.notificationDelegate.clearActiveAlarm() } }
        )
    }
}

private struct MainTabView: View {
    let deviceControlViewModel: DeviceControlViewModel

    var body: some View {
        TabView {
            RemoteControlView(viewModel: deviceControlViewModel)
                .tabItem { Label("Remote", systemImage: "bolt.fill") }

            AlarmsListView()
                .tabItem { Label("Alarms", systemImage: "alarm.fill") }

            FriendsRootView()
                .tabItem { Label("Friends", systemImage: "person.2.fill") }

            SettingsView(deviceControlViewModel: deviceControlViewModel)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

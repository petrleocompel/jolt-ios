import SwiftUI

struct RootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var deviceControlViewModel: DeviceControlViewModel?

    var body: some View {
        Group {
            if let viewModel = deviceControlViewModel {
                if viewModel.connectedDevice != nil {
                    MainTabView(deviceControlViewModel: viewModel)
                } else {
                    OnboardingView(viewModel: viewModel)
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

            SettingsView(deviceControlViewModel: deviceControlViewModel)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

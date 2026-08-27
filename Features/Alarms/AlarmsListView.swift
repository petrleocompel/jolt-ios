import SwiftUI

struct AlarmsListView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var viewModel: AlarmsViewModel?
    @State private var editingAlarm: Alarm?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    List {
                        ForEach(viewModel.alarms) { alarm in
                            AlarmRow(alarm: alarm) {
                                Task { await viewModel.toggle(alarm) }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { editingAlarm = alarm }
                        }
                        .onDelete { indexSet in
                            Task {
                                for index in indexSet {
                                    await viewModel.delete(viewModel.alarms[index])
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("alarmsList")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingAlarm = Alarm(location: .phone, hour: 7, minute: 0)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier("addAlarmButton")
                }
            }
            .task {
                if viewModel == nil {
                    viewModel = AlarmsViewModel(
                        alarmRepository: dependencies.alarmRepository,
                        deviceRepository: dependencies.deviceRepository,
                        phoneAlarmScheduler: dependencies.phoneAlarmScheduler
                    )
                }
                await viewModel?.load()
            }
            .sheet(item: $editingAlarm) { alarm in
                AlarmEditView(alarm: alarm) { updated in
                    Task { await viewModel?.save(updated) }
                }
            }
        }
    }
}

private struct AlarmRow: View {
    let alarm: Alarm
    let onToggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                    .font(.title2.monospacedDigit())
                Text(alarm.label.isEmpty ? alarm.location.displayName : alarm.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
        }
    }
}

private extension AlarmLocation {
    var displayName: String {
        switch self {
        case .device: return "Device alarm"
        case .phone: return "Phone alarm"
        }
    }
}

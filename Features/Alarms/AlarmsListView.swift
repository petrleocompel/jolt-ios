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
                        if viewModel.alarms.isEmpty {
                            // The app already uses `ContentUnavailableView`
                            // for empty poke activity; an empty alarm list
                            // was a blank screen with only a "+" in the bar.
                            ContentUnavailableView(
                                "No alarms",
                                systemImage: "alarm",
                                description: Text("Tap + to add one. Device alarms fire even when your phone is off.")
                            )
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        ForEach(viewModel.alarms) { alarm in
                            // A `Button` rather than `.onTapGesture`: a bare
                            // tap gesture carries no button trait, so
                            // VoiceOver announced the row as static text with
                            // no way to open it.
                            Button {
                                editingAlarm = alarm
                            } label: {
                                AlarmRow(alarm: alarm) {
                                    Task { await viewModel.toggle(alarm) }
                                }
                            }
                            .buttonStyle(.plain)
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
                    .errorBanner(viewModel.lastError) { viewModel.lastError = nil }
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
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                    .font(.title2.monospacedDigit())
                Text(alarm.label.isEmpty ? alarm.location.displayName : alarm.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { alarm.isEnabled }, set: { _ in onToggle() }))
                .labelsHidden()
                // `labelsHidden()` hides the label visually *and* from
                // VoiceOver, leaving the switch unnamed.
                .accessibilityLabel("\(alarm.label.isEmpty ? alarm.location.displayName : alarm.label) enabled")
                .accessibilityIdentifier("alarmToggle_\(alarm.id.uuidString)")
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

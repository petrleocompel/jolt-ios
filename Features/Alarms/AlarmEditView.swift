import SwiftUI

struct AlarmEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alarm: Alarm
    let onSave: (Alarm) -> Void

    init(alarm: Alarm, onSave: @escaping (Alarm) -> Void) {
        _alarm = State(initialValue: alarm)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Time",
                        selection: timeBinding,
                        displayedComponents: .hourAndMinute
                    )
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                }

                Section("Repeat") {
                    HStack(spacing: 4) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            let isSelected = alarm.repeatDays.contains(day)
                            Button(day.shortLabel) {
                                if isSelected {
                                    alarm.repeatDays.remove(day)
                                } else {
                                    alarm.repeatDays.insert(day)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(isSelected ? .accentColor : .secondary)
                            .font(.caption)
                            .fixedSize()
                            .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section("Where") {
                    Picker("Location", selection: $alarm.location) {
                        Text("Device").tag(AlarmLocation.device)
                        Text("Phone").tag(AlarmLocation.phone)
                    }
                    .pickerStyle(.segmented)
                    if alarm.location == .device {
                        Text("Fires from the wearable's own clock — works even if your phone is off or out of range.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("A local notification. May be silenced by Do Not Disturb or Focus — see README.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Stimulus") {
                    Picker("Kind", selection: $alarm.stimulus.kind) {
                        ForEach(StimulusKind.allCases) { kind in
                            Text(kind.displayName).tag(kind)
                        }
                    }
                    Stepper(
                        "Intensity: \(alarm.stimulus.intensity)",
                        value: $alarm.stimulus.intensity,
                        in: StimulusConfig.intensityRange
                    )
                }

                Section("Wake-up guarantee") {
                    Picker("Dismiss challenge", selection: $alarm.dismissChallenge) {
                        ForEach(DismissChallenge.allCases) { challenge in
                            Text(challenge.displayName).tag(challenge)
                        }
                    }
                }

                Section {
                    TextField("Label", text: $alarm.label)
                }
            }
            .navigationTitle(alarm.label.isEmpty ? "New alarm" : alarm.label)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(alarm)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveAlarmButton")
                }
            }
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: alarm.hour, minute: alarm.minute)) ?? .now
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                alarm.hour = components.hour ?? 0
                alarm.minute = components.minute ?? 0
            }
        )
    }
}

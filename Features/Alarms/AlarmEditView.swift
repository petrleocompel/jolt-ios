import SwiftUI

struct AlarmEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var alarm: Alarm
    let onSave: (Alarm) -> Void
    @State private var isScanningDismissCode = false

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

                Section {
                    Picker("Dismiss challenge", selection: $alarm.dismissChallenge) {
                        ForEach(DismissChallenge.allCases) { challenge in
                            Text(challenge.displayName).tag(challenge)
                        }
                    }
                    if alarm.dismissChallenge == .qrCodeScan {
                        Button {
                            isScanningDismissCode = true
                        } label: {
                            if alarm.dismissQRCode == nil {
                                Label("Scan code to save", systemImage: "qrcode.viewfinder")
                            } else {
                                Label("Code saved · Rescan", systemImage: "checkmark.circle.fill")
                            }
                        }
                        .accessibilityIdentifier("scanDismissCodeButton")
                    }
                } header: {
                    Text("Wake-up guarantee")
                } footer: {
                    if alarm.dismissChallenge == .qrCodeScan {
                        Text(alarm.dismissQRCode == nil
                             ? "Print a QR code or pick one on something you own, and keep it away from your bed. "
                                + "Until you save one, any QR code dismisses this alarm."
                             : "Only this code will dismiss the alarm — keep it somewhere away from your bed.")
                    }
                }

                Section {
                    TextField("Label", text: $alarm.label)
                }
            }
            .navigationTitle(alarm.label.isEmpty ? "New alarm" : alarm.label)
            .sheet(isPresented: $isScanningDismissCode) {
                DismissCodeScannerSheet { code in
                    alarm.dismissQRCode = code
                    isScanningDismissCode = false
                }
            }
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

/// Scans the QR code an alarm's QR challenge will require. The code is kept
/// even if the user later picks another challenge, so switching back (or
/// switching to QR from the ringing flow) doesn't need a rescan.
private struct DismissCodeScannerSheet: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                QRScannerView(onCodeScanned: onScanned)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .accessibilityLabel("Camera viewfinder")
                Text("Point the camera at the QR code you'll scan to dismiss this alarm.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .navigationTitle("Save dismiss code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

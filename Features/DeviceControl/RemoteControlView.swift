import SwiftUI

struct RemoteControlView: View {
    let viewModel: DeviceControlViewModel
    @State private var intensity: Double = 30
    @State private var repetitions: Int = 1

    var body: some View {
        NavigationStack {
            List {
                Section {
                    deviceStatusRow
                }

                Section("Intensity") {
                    let bounds = StimulusConfig.intensityRange
                    Slider(value: $intensity, in: Double(bounds.lowerBound)...Double(bounds.upperBound))
                        .accessibilityIdentifier("intensitySlider")
                    Stepper("Repetitions: \(repetitions)", value: $repetitions, in: 1...5)
                }

                Section("Fire") {
                    ForEach(StimulusKind.allCases) { kind in
                        Button(kind.displayName) {
                            viewModel.fire(StimulusConfig(kind: kind, intensity: Int(intensity), repetitions: repetitions))
                        }
                        .accessibilityIdentifier("fireButton_\(kind.rawValue)")
                    }
                }

                Section {
                    NavigationLink("Device info & diagnostics") {
                        DeviceDiagnosticsView(viewModel: viewModel)
                    }
                    NavigationLink("Button configuration") {
                        ButtonConfigView(viewModel: viewModel)
                    }
                    Button("Disconnect", role: .destructive) {
                        viewModel.disconnect()
                    }
                }
            }
            .navigationTitle("Remote")
            .accessibilityIdentifier("remoteControlScreen")
        }
    }

    private var deviceStatusRow: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text(viewModel.connectedDevice?.name ?? "Unknown device")
                    .font(.headline)
                Text(viewModel.connectedDevice?.family.displayName ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let battery = viewModel.connectedDevice?.info.batteryLevelPercent {
                Label("\(battery)%", systemImage: "battery.100")
                    .font(.caption)
            }
        }
        .accessibilityIdentifier("deviceStatusRow")
    }
}

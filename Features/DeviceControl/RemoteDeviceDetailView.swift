import SwiftUI

/// Restyled front door for the connected device — a summary card plus the
/// same two destinations the old Remote screen linked directly:
/// `DeviceDiagnosticsView` (GATT dump, protocol lab, Bluetooth log, stimulus
/// characteristic remapping — unchanged) and `ButtonConfigView` (unchanged).
/// Diagnostics moves one level deeper; nothing it does is removed.
struct RemoteDeviceDetailView: View {
    let viewModel: DeviceControlViewModel

    @State private var info: DeviceInfo?
    @State private var loadError: String?

    private var device: PavlokDevice? { viewModel.connectedDevice }
    private var isConnected: Bool { device != nil }

    var body: some View {
        List {
            Section {
                heroCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Device") {
                LabeledContent("Model", value: info?.modelNumber ?? device?.family.displayName ?? "—")
                LabeledContent("Serial", value: info?.serialNumber ?? "—")
                LabeledContent("Firmware", value: info?.firmwareRevision ?? "—")
                LabeledContent("Hardware", value: info?.hardwareRevision ?? "—")
                LabeledContent("Manufacturer", value: info?.manufacturer ?? "—")
                LabeledContent("Battery", value: info?.batteryLevelPercent.map { "\($0)%" }
                    ?? device?.info.batteryLevelPercent.map { "\($0)%" } ?? "—")
                if let loadError {
                    Text(loadError).font(.footnote).foregroundStyle(.red)
                }
            }

            Section {
                NavigationLink {
                    DeviceDiagnosticsView(viewModel: viewModel)
                } label: {
                    Label("GATT inspector & diagnostics", systemImage: "stethoscope")
                }
                NavigationLink {
                    ButtonConfigView(viewModel: viewModel)
                } label: {
                    Label("Button configuration", systemImage: "button.horizontal.top.press")
                }
            }

            Section {
                Button(role: .destructive) {
                    viewModel.disconnect()
                } label: {
                    Text("Disconnect").frame(maxWidth: .infinity)
                }
                .disabled(!isConnected)
                .accessibilityIdentifier("disconnectButton")
            }
        }
        .navigationTitle(device?.name ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.16))
                Image(systemName: "bolt.fill").font(.title2).foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)

            VStack(spacing: 4) {
                Text(device?.name ?? "No device")
                    .font(.remoteNumeral(22))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.caption.weight(.semibold))
                    .tracking(1.0)
                    .foregroundStyle(isConnected ? Color.accentColor : .white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .remoteCard(isConnected ? .device : .neutral)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var statusLine: String {
        guard isConnected else { return "NOT CONNECTED" }
        if let battery = info?.batteryLevelPercent ?? device?.info.batteryLevelPercent {
            return "CONNECTED · \(battery)%"
        }
        return "CONNECTED"
    }

    private func load() async {
        guard isConnected else { return }
        do {
            info = try await viewModel.readDeviceInfo()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

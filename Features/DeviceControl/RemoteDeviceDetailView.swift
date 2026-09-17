import SwiftUI

/// Restyled front door for the connected device — a summary card, pairing a
/// replacement, and the developer destinations: `DeviceDiagnosticsView` (GATT
/// dump, stimulus characteristic remapping), Protocol lab and Bluetooth log
/// (also still linked from Diagnostics), and `ButtonConfigView`.
struct RemoteDeviceDetailView: View {
    let viewModel: DeviceControlViewModel

    @State private var info: DeviceInfo?
    @State private var loadError: String?
    @State private var isShowingPairSheet = false

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
                Button {
                    isShowingPairSheet = true
                } label: {
                    HStack {
                        Label("Pair a different device", systemImage: "plus")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .accessibilityIdentifier("pairDifferentDeviceButton")
                NavigationLink {
                    DeviceDiagnosticsView(viewModel: viewModel)
                } label: {
                    Label("GATT inspector & diagnostics", systemImage: "stethoscope")
                }
                NavigationLink {
                    GATTLoadingProtocolLab(viewModel: viewModel)
                } label: {
                    Label("Protocol lab", systemImage: "text.alignleft")
                }
                NavigationLink {
                    BluetoothLogView()
                } label: {
                    Label("Bluetooth log", systemImage: "list.bullet.rectangle")
                }
                NavigationLink {
                    ButtonConfigView(viewModel: viewModel)
                } label: {
                    Label("Button configuration", systemImage: "button.horizontal.top.press")
                }
            }

            if isConnected {
                Section {
                    Button(role: .destructive) {
                        viewModel.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.red.opacity(0.5))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("disconnectButton")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(device?.name ?? viewModel.pairedDeviceName ?? "Device")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingPairSheet) {
            PairDeviceSheet(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
        .task { await load() }
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(statusTint.opacity(0.16))
                Image(systemName: "bolt.fill").font(.system(size: 36)).foregroundStyle(statusTint)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 6) {
                Text(device?.name ?? viewModel.pairedDeviceName ?? "No device")
                    .font(.remoteNumeral(26, weight: .bold))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.subheadline.weight(.semibold))
                    .tracking(1.2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(statusTint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .remoteCard(isConnected ? .device : .neutral)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var statusTint: Color {
        if isConnected { return .accentColor }
        return viewModel.hasPairedDevice ? .orange : .white.opacity(0.5)
    }

    private var statusLine: String {
        guard isConnected else {
            return viewModel.hasPairedDevice ? "NOT CONNECTED · Out of range or switched off" : "NO DEVICE"
        }
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

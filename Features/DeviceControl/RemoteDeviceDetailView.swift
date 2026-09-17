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
        .sheet(isPresented: $isShowingPairSheet) {
            PairDeviceSheet(viewModel: viewModel)
        }
        .task { await load() }
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.16))
                Image(systemName: "bolt.fill").font(.system(size: 36)).foregroundStyle(Color.accentColor)
            }
            .frame(width: 84, height: 84)

            VStack(spacing: 6) {
                Text(device?.name ?? "No device")
                    .font(.remoteNumeral(26, weight: .bold))
                    .foregroundStyle(.white)
                Text(statusLine)
                    .font(.subheadline.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(isConnected ? Color.accentColor : .white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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

/// Protocol lab needs the GATT table to offer writable characteristics.
/// Diagnostics hands over the dump it already has; reached from here there
/// is none yet, so read one (without values — only the table is needed).
private struct GATTLoadingProtocolLab: View {
    let viewModel: DeviceControlViewModel

    @State private var gatt: [GATTCharacteristicDump]?
    @State private var loadError: String?

    var body: some View {
        if let gatt {
            ProtocolLabView(viewModel: viewModel, gatt: gatt)
        } else if let loadError {
            ContentUnavailableView("Couldn't read the device", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else {
            ProgressView()
                .task {
                    do {
                        gatt = try await viewModel.dumpGATT(readingValues: false)
                    } catch {
                        loadError = error.localizedDescription
                    }
                }
        }
    }
}

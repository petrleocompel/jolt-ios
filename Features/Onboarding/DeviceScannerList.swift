import SwiftUI

/// The device-picking half of pairing: which family to look for, live scan
/// results, and the scan toggle.
///
/// Shown inside `PairDeviceSheet`, which the first-run screen, Settings,
/// Device detail and the Remote tab's device card all open, so pairing
/// behaves — and looks — the same wherever you reach for it.
struct DeviceScannerList: View {
    let viewModel: DeviceControlViewModel

    /// One family at a time: the families advertise different names and
    /// services, and a scan for exactly the one you own finds it faster and
    /// can't offer a neighbour's different model by mistake.
    @State private var family: DeviceFamily = .pavlok3
    @State private var isScanning = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                familyPicker
                    .padding(.top, 22)

                if isScanning && viewModel.discoveredDevices.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("Scanning…").foregroundStyle(.secondary)
                    }
                    .padding(.top, 34)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("scanningIndicator")
                }

                if isScanning && !viewModel.discoveredDevices.isEmpty {
                    discoveredDevices.padding(.top, 28)
                }

                scanButton.padding(.top, 36)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        // A scan left running after the sheet closes keeps the radio busy for
        // nothing.
        .onDisappear {
            guard isScanning else { return }
            isScanning = false
            viewModel.stopScan()
        }
        .onChange(of: family) { _, newFamily in
            guard isScanning else { return }
            viewModel.startScan(for: [newFamily])
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(width: 88, height: 88)
            .padding(.bottom, 10)
            .accessibilityHidden(true)

            Text("Find your Pavlok")
                .font(.title2.bold())
            Text("Make sure your device is charged and nearby, then start scanning.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Wraps onto a second line when the three chips don't fit side by side
    /// (narrow phones, larger Dynamic Type).
    private var familyPicker: some View {
        ViewThatFits {
            HStack(spacing: 8) { familyChips(DeviceFamily.allCases) }
            VStack(spacing: 8) {
                HStack(spacing: 8) { familyChips(Array(DeviceFamily.allCases.prefix(2))) }
                HStack(spacing: 8) { familyChips(Array(DeviceFamily.allCases.dropFirst(2))) }
            }
        }
        .accessibilityIdentifier("deviceFamilyPicker")
    }

    private func familyChips(_ families: [DeviceFamily]) -> some View {
        ForEach(families, id: \.self) { candidate in
            let isSelected = candidate == family
            Button {
                family = candidate
            } label: {
                Text(candidate.displayName)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor.opacity(0.16) : Color(.secondarySystemBackground))
                    )
                    .overlay(
                        Capsule().strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private var discoveredDevices: some View {
        VStack(spacing: 0) {
            Divider()
            ForEach(viewModel.discoveredDevices) { device in
                Button {
                    viewModel.connect(to: device)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name).font(.title3.weight(.semibold))
                            Text(subtitle(for: device)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .connecting = viewModel.connectionState {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("discoveredDevice_\(device.name)")
                Divider()
            }
        }
    }

    private func subtitle(for device: PavlokDevice) -> String {
        guard let rssi = device.rssi else { return device.family.displayName }
        return "\(device.family.displayName) · \(rssi < 0 ? "\u{2212}\(-rssi)" : "\(rssi)") dBm"
    }

    private var scanButton: some View {
        Button {
            isScanning.toggle()
            if isScanning {
                viewModel.startScan(for: [family])
            } else {
                viewModel.stopScan()
            }
        } label: {
            Text(isScanning ? "Stop scanning" : "Start scanning")
                .font(.title3.weight(.medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .accessibilityIdentifier("toggleScanButton")
    }
}

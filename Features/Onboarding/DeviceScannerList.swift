import SwiftUI

/// The device-picking half of pairing: family filter, live scan results, and
/// the scan toggle.
///
/// Shared by the first-run `OnboardingView` and the `PairDeviceSheet` that
/// Settings and the Remote tab's device card open later, so pairing behaves
/// the same whenever you reach for it — the first run is no longer the only
/// moment you can pair.
struct DeviceScannerList: View {
    let viewModel: DeviceControlViewModel

    @State private var selectedFamilies: Set<DeviceFamily> = Set(DeviceFamily.allCases)
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 16) {
            deviceFamilyPicker

            if isScanning && viewModel.discoveredDevices.isEmpty {
                ProgressView("Scanning…")
                    .accessibilityIdentifier("scanningIndicator")
            }

            List(viewModel.discoveredDevices) { device in
                Button {
                    viewModel.connect(to: device)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name).font(.headline)
                            Text(device.family.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .connecting = viewModel.connectionState {
                            ProgressView()
                        }
                    }
                }
                .accessibilityIdentifier("discoveredDevice_\(device.name)")
            }
            .listStyle(.plain)

            Button(isScanning ? "Stop scanning" : "Start scanning") {
                isScanning.toggle()
                if isScanning {
                    viewModel.startScan(for: selectedFamilies)
                } else {
                    viewModel.stopScan()
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("toggleScanButton")
        }
        // A scan left running after the sheet closes keeps the radio busy for
        // nothing — the first-run screen could get away without this because
        // it only ever went away by connecting.
        .onDisappear {
            guard isScanning else { return }
            isScanning = false
            viewModel.stopScan()
        }
    }

    private var deviceFamilyPicker: some View {
        HStack {
            ForEach(DeviceFamily.allCases, id: \.self) { family in
                let isSelected = selectedFamilies.contains(family)
                Button(family.displayName) {
                    if isSelected {
                        selectedFamilies.remove(family)
                    } else {
                        selectedFamilies.insert(family)
                    }
                }
                .buttonStyle(.bordered)
                .tint(isSelected ? .accentColor : .secondary)
            }
        }
        .accessibilityIdentifier("deviceFamilyPicker")
    }
}

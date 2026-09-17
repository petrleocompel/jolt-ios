import SwiftUI

/// The device-picking half of pairing: header, family filter, live scan
/// results, and the scan toggle.
///
/// Shared by the first-run `OnboardingView` and the `PairDeviceSheet` that
/// Settings, Device detail and the Remote tab's device card open later, so
/// pairing behaves — and looks — the same whenever you reach for it.
///
/// `footer` sits under the scan button; the first run puts "Continue without
/// a device" there.
struct DeviceScannerList<Footer: View>: View {
    let viewModel: DeviceControlViewModel
    @ViewBuilder let footer: () -> Footer

    @State private var selectedFamilies: Set<DeviceFamily> = Set(DeviceFamily.allCases)
    @State private var isScanning = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                deviceFamilyPicker
                discoveredDevices
            }
            .padding(.horizontal)
            .padding(.top, 24)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                scanButton
                footer()
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
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

    private var header: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(width: 96, height: 96)
            .padding(.bottom, 10)
            .accessibilityHidden(true)

            Text("Find your Pavlok")
                .font(.title2.bold())
            Text("Make sure your device is charged and nearby, then start scanning.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Wraps onto a second line when the three chips don't fit side by side
    /// (narrow phones, larger Dynamic Type).
    private var deviceFamilyPicker: some View {
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
        ForEach(families, id: \.self) { family in
            let isSelected = selectedFamilies.contains(family)
            Button {
                if isSelected {
                    selectedFamilies.remove(family)
                } else {
                    selectedFamilies.insert(family)
                }
            } label: {
                Text(family.displayName)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .background(
                        Capsule().fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    @ViewBuilder
    private var discoveredDevices: some View {
        if isScanning && viewModel.discoveredDevices.isEmpty {
            ProgressView("Scanning…")
                .accessibilityIdentifier("scanningIndicator")
        }

        if !viewModel.discoveredDevices.isEmpty {
            VStack(spacing: 0) {
                Divider()
                ForEach(viewModel.discoveredDevices) { device in
                    Button {
                        viewModel.connect(to: device)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.name).font(.title3.weight(.semibold))
                                Text(device.family.displayName).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if case .connecting = viewModel.connectionState {
                                ProgressView()
                            }
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discoveredDevice_\(device.name)")
                    Divider()
                }
            }
        }
    }

    private var scanButton: some View {
        Button {
            isScanning.toggle()
            if isScanning {
                viewModel.startScan(for: selectedFamilies)
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

extension DeviceScannerList where Footer == EmptyView {
    init(viewModel: DeviceControlViewModel) {
        self.init(viewModel: viewModel, footer: { EmptyView() })
    }
}

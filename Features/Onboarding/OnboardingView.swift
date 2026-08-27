import SwiftUI

struct OnboardingView: View {
    let viewModel: DeviceControlViewModel
    @State private var selectedFamilies: Set<DeviceFamily> = Set(DeviceFamily.allCases)
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    Text("Find your Pavlok")
                        .font(.title2.bold())
                    Text("Make sure your device is charged and nearby, then start scanning.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

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

                Spacer()

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
                .padding(.bottom, 24)
            }
            .padding(.horizontal)
            .navigationTitle("Pair device")
            .alert("Connection failed", isPresented: errorBinding) {
                Button("OK") { viewModel.lastError = nil }
            } message: {
                Text(viewModel.lastError ?? "")
            }
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

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.lastError != nil }, set: { if !$0 { viewModel.lastError = nil } })
    }
}

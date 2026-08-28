import SwiftUI

struct DeviceDiagnosticsView: View {
    let viewModel: DeviceControlViewModel

    @State private var info: DeviceInfo?
    @State private var gatt: [GATTCharacteristicDump] = []
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        List {
            deviceSection
            gattSection
            stimulusMappingSection
            NavigationLink("Protocol lab") {
                ProtocolLabView(viewModel: viewModel, gatt: gatt)
            }
            NavigationLink("Bluetooth log") {
                BluetoothLogView()
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var deviceSection: some View {
        Section("Device") {
            if isLoading && info == nil {
                ProgressView().frame(maxWidth: .infinity)
            }
            LabeledContent("Model", value: info?.modelNumber ?? "—")
            LabeledContent("Serial", value: info?.serialNumber ?? "—")
            LabeledContent("Firmware", value: info?.firmwareRevision ?? "—")
            LabeledContent("Hardware", value: info?.hardwareRevision ?? "—")
            LabeledContent("Software", value: info?.softwareRevision ?? "—")
            LabeledContent("Manufacturer", value: info?.manufacturer ?? "—")
            LabeledContent("Battery", value: info?.batteryLevelPercent.map { "\($0)%" } ?? "—")
            if let loadError {
                Text(loadError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// The device's real GATT table. While the Pavlok wire protocol is only
    /// partly recovered this is the highest-value screen in the app: it says
    /// whether a stimulus that "did nothing" was sent to a characteristic
    /// that exists at all.
    private var gattSection: some View {
        Section {
            if gatt.isEmpty {
                Text(isLoading ? "Reading…" : "No services discovered.")
                    .foregroundStyle(.secondary)
            }
            ForEach(groupedServices, id: \.service) { group in
                DisclosureGroup("Service \(group.service)") {
                    ForEach(group.characteristics) { characteristic in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(characteristic.uuid)
                                .font(.callout.monospaced())
                            Text(characteristic.properties.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("GATT table")
        } footer: {
            if !gatt.isEmpty {
                ShareLink(item: gatt.transcript) {
                    Label("Share GATT dump", systemImage: "square.and.arrow.up")
                        .font(.footnote)
                }
                .accessibilityIdentifier("shareGATTDumpButton")
            }
        }
    }

    /// Which characteristic each stimulus is written to.
    ///
    /// This is user-editable because the mapping in `LegacyGATT` is inferred
    /// from constant *names* recovered out of the Android binary, not from a
    /// capture of real traffic — see that file's header. If Zap does nothing
    /// and Vibe works, the two are swapped, and this is where to fix it
    /// without a rebuild.
    private var stimulusMappingSection: some View {
        Section {
            ForEach(StimulusKind.allCases) { kind in
                StimulusCharacteristicPicker(kind: kind, options: writableCharacteristics)
            }
        } header: {
            Text("Stimulus characteristics")
        } footer: {
            Text("Only change these if a stimulus does nothing or fires the wrong output. Test with Beep first.")
        }
    }

    private var writableCharacteristics: [GATTCharacteristicDump] {
        gatt.filter(\.isWritable).sorted { $0.uuid < $1.uuid }
    }

    private var groupedServices: [(service: String, characteristics: [GATTCharacteristicDump])] {
        Dictionary(grouping: gatt, by: \.serviceUUID)
            .map { (service: $0.key, characteristics: $0.value.sorted { $0.uuid < $1.uuid }) }
            .sorted { $0.service < $1.service }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            info = try await viewModel.readDeviceInfo()
            gatt = try await viewModel.dumpGATT()
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct StimulusCharacteristicPicker: View {
    let kind: StimulusKind
    let options: [GATTCharacteristicDump]

    private let store = LegacyProtocolStore()
    @State private var selection: String = ""

    var body: some View {
        Picker(kind.displayName, selection: $selection) {
            // The current value may not be in `options` — either nothing has
            // been discovered yet, or the inferred default genuinely isn't
            // on this device, which is itself worth seeing.
            if !options.contains(where: { $0.uuid == selection }) {
                Text("\(selection) (not found)").tag(selection)
            }
            ForEach(options) { option in
                Text(option.uuid).tag(option.uuid)
            }
        }
        .accessibilityIdentifier("stimulusCharacteristicPicker_\(kind.rawValue)")
        .onAppear { selection = store.characteristicUUIDString(for: kind) }
        .onChange(of: selection) { _, newValue in
            guard !newValue.isEmpty, newValue != store.characteristicUUIDString(for: kind) else { return }
            store.setCharacteristicUUIDString(newValue, for: kind)
            BLELog.info("Stimulus \(kind.rawValue) remapped to characteristic \(newValue)")
        }
    }
}

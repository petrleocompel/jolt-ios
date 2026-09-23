import SwiftUI
import UIKit

struct DeviceDiagnosticsView: View {
    let viewModel: DeviceControlViewModel

    @State private var gatt: [GATTCharacteristicDump] = []
    @State private var isLoading = false
    @State private var isReadingValues = false
    @State private var loadError: String?
    @State private var didCopyGATT = false
    /// Bumped by "Reset to defaults" to force the pickers to re-read the
    /// store; they hold their selection in local state.
    @State private var resetToken = UUID()

    // Live events. Owned here rather than by `DeviceEventCaptureView` so the
    // subscription survives pushing Protocol lab or the Bluetooth log — the
    // point is to press the device's button and read what it said.
    @State private var eventLog = BLEEventLog.shared
    @State private var isListening = false
    @State private var isStartingListening = false
    @State private var subscribedCount = 0
    @State private var listenError: String?

    /// Read off the published device rather than kept locally: the refresh
    /// below republishes what it read, so this screen and the dashboard card
    /// always show the same battery percentage.
    private var info: DeviceInfo? { viewModel.connectedDevice?.info }

    /// False once this screen is popped, as opposed to merely covered by a
    /// pushed child — see `onDisappear`.
    @Environment(\.isPresented) private var isPresented

    var body: some View {
        List {
            deviceSection
            gattSection
            stimulusMappingSection
            liveEventsSection
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: gatt.transcript) {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(gatt.isEmpty)
                .accessibilityLabel("Share GATT dump")
                .accessibilityIdentifier("shareGATTDumpButton")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        // Subscriptions cost battery and keep the radio busy, so they don't
        // outlive the screen that asked for them. Pushing a child also fires
        // `onDisappear`; only a real pop should stop listening.
        .onDisappear {
            guard !isPresented, isListening else { return }
            viewModel.stopListeningForDeviceEvents()
            isListening = false
        }
    }

    private var deviceSection: some View {
        Section("Device") {
            if isLoading && info?.modelNumber == nil {
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
        Section("GATT table") {
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
                            if let value = characteristic.value {
                                Text(value.isEmpty ? "(empty)" : value)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }

            // Reads can't fire a stimulus, so this is safe to run on an
            // unidentified characteristic — unlike a write. What a config
            // characteristic already holds is usually enough to say which
            // output it drives.
            Button {
                Task { await load(readingValues: true) }
            } label: {
                if isReadingValues {
                    HStack { ProgressView(); Text("Reading…") }
                } else {
                    Label("Read all values", systemImage: "arrow.down.doc")
                }
            }
            .disabled(isLoading)
            .accessibilityIdentifier("readAllValuesButton")

            Button {
                UIPasteboard.general.string = gatt.transcript
                didCopyGATT = true
            } label: {
                Label(didCopyGATT ? "Copied" : "Copy GATT dump", systemImage: "doc.on.doc")
            }
            .disabled(gatt.isEmpty)
            .accessibilityIdentifier("copyGATTDumpButton")
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
                    .id("\(kind.rawValue)-\(resetToken)")
            }
            Button("Reset to defaults", role: .destructive) {
                LegacyProtocolStore().reset()
                resetToken = UUID()
            }
            .accessibilityIdentifier("resetStimulusMappingButton")
        } header: {
            Text("Stimulus characteristics")
        } footer: {
            Text("Remapping writes to a different characteristic. See docs/RE-FINDINGS.md before changing anything. "
                + "Only remap if a stimulus does nothing or fires the wrong output; read all values first, then test with Beep.")
        }
    }

    private var liveEventsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { isListening }, set: { setListening($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listen for device events")
                    if isListening, !isStartingListening {
                        Text("Listening on \(subscribedCount) characteristic\(subscribedCount == 1 ? "" : "s")")
                            .font(.footnote)
                            .foregroundStyle(.tint)
                    }
                }
            }
            .disabled(isStartingListening)
            .accessibilityIdentifier("listenForDeviceEventsToggle")

            if let listenError {
                Text(listenError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            // Only shown once there's something to look at, so the section
            // matches the design until listening actually produces events.
            if isListening || capturedEventCount > 0 {
                NavigationLink {
                    DeviceEventCaptureView(isListening: isListening)
                } label: {
                    LabeledContent("Captured events", value: "\(capturedEventCount)")
                }
                .accessibilityIdentifier("capturedEventsLink")
            }

            NavigationLink {
                ProtocolLabView(viewModel: viewModel, gatt: gatt)
            } label: {
                Text("Protocol lab").foregroundStyle(.tint)
            }
            .accessibilityIdentifier("protocolLabLink")
            NavigationLink {
                BluetoothLogView()
            } label: {
                Text("Bluetooth log").foregroundStyle(.tint)
            }
            .accessibilityIdentifier("bluetoothLogLink")
        } header: {
            Text("Live events")
        } footer: {
            Text("Listening subscribes to button presses and battery notifications. It drains the device faster. "
                + "Protocol lab opens with the table already read here.")
        }
    }

    private var capturedEventCount: Int {
        eventLog.events.lazy.filter(DeviceEventCaptureView.isCapturedEvent).count
    }

    private func setListening(_ isOn: Bool) {
        listenError = nil
        guard isOn else {
            viewModel.stopListeningForDeviceEvents()
            isListening = false
            return
        }
        isListening = true
        isStartingListening = true
        Task {
            defer { isStartingListening = false }
            do {
                subscribedCount = try await viewModel.startListeningForDeviceEvents()
                if subscribedCount == 0 {
                    isListening = false
                    listenError = "No notifying characteristics could be subscribed."
                }
            } catch {
                isListening = false
                listenError = error.localizedDescription
            }
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

    private func load(readingValues: Bool = false) async {
        isLoading = true
        isReadingValues = readingValues
        loadError = nil
        defer {
            isLoading = false
            isReadingValues = false
        }
        do {
            _ = try await viewModel.readDeviceInfo()
            gatt = try await viewModel.dumpGATT(readingValues: readingValues)
            didCopyGATT = false
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// A row reading "Zap   156E1001 · remap", as in the design, that opens a menu
/// of the device's writable characteristics. A `Menu` wrapping a `Picker`
/// rather than a bare menu-style `Picker`, because the latter can only show
/// the selected option's own label as its value.
private struct StimulusCharacteristicPicker: View {
    let kind: StimulusKind
    let options: [GATTCharacteristicDump]

    private let store = LegacyProtocolStore()
    @State private var selection: String = ""

    var body: some View {
        Menu {
            Picker(kind.displayName, selection: $selection) {
                // The current value may not be in `options` — either nothing
                // has been discovered yet, or the inferred default genuinely
                // isn't on this device, which is itself worth seeing.
                if !options.contains(where: { $0.uuid == selection }) {
                    Text("\(selection) (not found)").tag(selection)
                }
                ForEach(options) { option in
                    Text(option.uuid).tag(option.uuid)
                }
            }
        } label: {
            HStack {
                Text(kind.displayName)
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("\(ProtocolLabView.shortUUID(selection)) · remap")
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
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

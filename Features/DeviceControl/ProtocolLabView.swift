import SwiftUI

/// Sends arbitrary bytes to an arbitrary characteristic.
///
/// The Pavlok 2/3 payload layout is reconstructed from field names, not from
/// a capture (see `LegacyDeviceController`). Rather than guess again in
/// source and rebuild each time, this screen makes the guess adjustable at
/// runtime with the hardware in hand: pick a characteristic from what the
/// device actually exposes, type the bytes, choose the write type, send, and
/// read the result right here or in the Bluetooth log.
///
/// Not reachable from any normal flow — device detail and Diagnostics only.
struct ProtocolLabView: View {
    let viewModel: DeviceControlViewModel
    let gatt: [GATTCharacteristicDump]

    @State private var selectedID: String = ""
    /// Whether the hex field still holds a prefilled value, so typing isn't
    /// overwritten when the selection is re-applied.
    @State private var isHexUserEdited = false
    @State private var hexInput: String = "01 14"
    @State private var mode: RawWriteMode = .withResponse
    @State private var exchange: [ExchangeLine] = []
    @State private var isSending = false

    /// Enough to compare a handful of attempts side by side; the full history
    /// is in the Bluetooth log.
    static let exchangeLimit = 20

    private var writable: [GATTCharacteristicDump] {
        gatt.filter(\.isWritable).sorted { ($0.serviceUUID, $0.uuid) < ($1.serviceUUID, $1.uuid) }
    }

    private var selected: GATTCharacteristicDump? {
        writable.first { $0.id == selectedID }
    }

    private var parsedBytes: [UInt8]? {
        Self.parseHex(hexInput)
    }

    var body: some View {
        Form {
            writeSection
            exchangeSection
        }
        .navigationTitle("Protocol lab")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Not in the design, but the lab is useless without the log: a
            // write-without-response has no other feedback at all.
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    BluetoothLogView()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .accessibilityLabel("Bluetooth log")
            }
        }
        .accessibilityIdentifier("protocolLabScreen")
    }

    // MARK: Write

    private var writeSection: some View {
        Section {
            if writable.isEmpty {
                Text("No writable characteristics discovered. Connect a device and reload Diagnostics.")
                    .foregroundStyle(.secondary)
            } else {
                characteristicPicker
                payloadField
                if let summary = validationSummary {
                    Text(summary.text)
                        .font(.footnote.monospaced())
                        .foregroundStyle(summary.isError ? Color.red : Color.secondary)
                }
                modePicker
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Text("Send payload")
                        if isSending {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(selected == nil || parsedBytes == nil || isSending || !selectedSupports(mode))
                .accessibilityIdentifier("protocolLabSendButton")
            }
        } header: {
            Text("Write to characteristic")
        } footer: {
            Text("Raw writes bypass every cap and cooldown in the app. Keep the device off your wrist. "
                + "Start with the characteristic you believe is Beep — an unknown one could be the zap output.")
        }
    }

    private var characteristicPicker: some View {
        Picker("Characteristic", selection: $selectedID) {
            // No default target on purpose: preselecting one would make
            // "Send payload" one tap away from writing to something that
            // might be the zap output.
            Text("Choose…").tag("")
            ForEach(writable) { characteristic in
                Text(Self.label(for: characteristic, among: writable))
                    .font(.body.monospaced())
                    .tag(characteristic.id)
            }
        }
        .accessibilityIdentifier("protocolLabTargetPicker")
        // Prefill with what the characteristic currently holds. A
        // wrong-length write is rejected outright, so starting from the
        // device's own value and changing one byte is both the safest and the
        // fastest way to find a layout.
        .onChange(of: selectedID) { _, _ in
            if !selectedSupports(mode), let fallback = RawWriteMode.allCases.first(where: selectedSupports) {
                mode = fallback
            }
            guard !isHexUserEdited, let value = selected?.value, !value.isEmpty else { return }
            hexInput = value
        }
    }

    private var payloadField: some View {
        HStack {
            Text("Payload")
            TextField("01 14", text: $hexInput)
                .font(.body.monospaced())
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                .accessibilityIdentifier("protocolLabHexField")
                .onChange(of: hexInput) { _, _ in isHexUserEdited = true }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(RawWriteMode.allCases) { option in
                Text(option.displayName)
                    .tag(option)
                    // CoreBluetooth silently drops a write type the
                    // characteristic doesn't declare, so don't offer it.
                    .selectionDisabled(!selectedSupports(option))
            }
        }
        .accessibilityIdentifier("protocolLabModePicker")
    }

    /// One compact line under the payload: what will be sent, what the device
    /// declares, and what it currently holds — the three things that decide
    /// whether a write is worth trying.
    private var validationSummary: (text: String, isError: Bool)? {
        guard let bytes = parsedBytes else {
            return hexInput.isEmpty ? nil : ("Not valid hex — use pairs like 01 14.", true)
        }
        var parts = ["\(bytes.count) byte\(bytes.count == 1 ? "" : "s")"]
        if let selected {
            parts.append(selected.properties.joined(separator: ", "))
            if let value = selected.value {
                let held = value.split(separator: " ").count
                parts.append("holds \(value.isEmpty ? "(empty)" : value)")
                if held > 0, held != bytes.count {
                    return (parts.joined(separator: " · ") + " — length differs", true)
                }
            }
        }
        return (parts.joined(separator: " · "), false)
    }

    private func selectedSupports(_ option: RawWriteMode) -> Bool {
        // Before a target is chosen, both stay selectable.
        guard let selected else { return true }
        return selected.properties.contains(option.requiredProperty)
    }

    // MARK: Exchange

    private var exchangeSection: some View {
        Section("Last exchange") {
            if exchange.isEmpty {
                Text("Nothing sent from here yet.")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(exchange) { line in
                        Text(line.text)
                            .foregroundStyle(line.kind.color)
                    }
                }
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    private func send() async {
        guard let selected, let bytes = parsedBytes else { return }
        isSending = true
        defer { isSending = false }
        let target = Self.label(for: selected, among: writable)
        append(ExchangeLine(text: "→ \(target) · \(Self.formatHex(bytes))", kind: .sent))
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await viewModel.writeRaw(
                Data(bytes),
                characteristicUUID: selected.uuid,
                serviceUUID: selected.serviceUUID,
                mode: mode
            )
            let milliseconds = Int(((clock.now - start) / .milliseconds(1)).rounded())
            switch mode {
            case .withResponse:
                append(ExchangeLine(text: "← ACK · \(milliseconds) ms", kind: .ack))
            case .withoutResponse:
                // Nothing comes back for this write type; saying "ACK" would
                // claim a confirmation the device never gave.
                append(ExchangeLine(text: "← sent, no response expected", kind: .neutral))
            }
        } catch {
            append(ExchangeLine(text: "← \(error.localizedDescription)", kind: .error))
        }
    }

    private func append(_ line: ExchangeLine) {
        exchange.append(line)
        if exchange.count > Self.exchangeLimit {
            exchange.removeFirst(exchange.count - Self.exchangeLimit)
        }
    }

    // MARK: Formatting

    /// Accepts "1401", "14 01", "0x14 0x01". Returns nil for anything that
    /// isn't a whole number of bytes.
    static func parseHex(_ input: String) -> [UInt8]? {
        let cleaned = input
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .filter { !$0.isWhitespace && $0 != "," }
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    static func formatHex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    /// "156E1001-A300-…" → "156E1001". The first group is what differs
    /// between Pavlok's vendor characteristics; the rest is a shared base.
    static func shortUUID(_ uuid: String) -> String {
        uuid.split(separator: "-").first.map(String.init) ?? uuid
    }

    /// The short UUID, qualified with its service only when another writable
    /// characteristic shares it — so the picker stays terse without ever
    /// becoming ambiguous.
    static func label(for characteristic: GATTCharacteristicDump, among all: [GATTCharacteristicDump]) -> String {
        let short = shortUUID(characteristic.uuid)
        let isAmbiguous = all.contains { $0.id != characteristic.id && shortUUID($0.uuid) == short }
        return isAmbiguous ? "\(shortUUID(characteristic.serviceUUID))/\(short)" : short
    }
}

private struct ExchangeLine: Identifiable {
    enum Kind {
        case sent, ack, neutral, error

        var color: Color {
            switch self {
            case .sent, .neutral: .secondary
            case .ack: .accentColor
            case .error: .red
            }
        }
    }

    let id = UUID()
    let text: String
    let kind: Kind
}

/// Protocol lab needs the GATT table to offer writable characteristics.
/// Diagnostics hands over the dump it already has; reached from device
/// detail there is none yet, so read one (without values — only the table is
/// needed), with a visible spinner and a retryable failure since discovery on
/// a flaky link is exactly when someone opens this screen.
struct GATTLoadingProtocolLab: View {
    let viewModel: DeviceControlViewModel

    @State private var gatt: [GATTCharacteristicDump]?
    @State private var loadError: String?
    /// Bumped by "Retry read" to restart the `.task`.
    @State private var attempt = 0

    var body: some View {
        if let gatt {
            ProtocolLabView(viewModel: viewModel, gatt: gatt)
        } else {
            ScrollView {
                if let loadError {
                    failedCard(loadError)
                        .padding(.horizontal, 16)
                        .padding(.top, 60)
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.accentColor)
                        Text("Reading GATT table…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                    .accessibilityIdentifier("protocolLabReading")
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Protocol lab")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: attempt) { await load() }
        }
    }

    private func failedCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("READ FAILED")
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.red)
            Text("Couldn't read the GATT table")
                .font(.title3.weight(.semibold))
                .padding(.top, 6)
            Text("\(message) Protocol lab needs the table before it can write anything.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Button {
                loadError = nil
                attempt += 1
            } label: {
                Text("Retry read")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Capsule().fill(Color.primary.opacity(0.10)))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .accessibilityIdentifier("protocolLabRetryButton")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.red.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.red.opacity(0.5)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("protocolLabReadFailed")
    }

    private func load() async {
        do {
            gatt = try await viewModel.dumpGATT(readingValues: false)
        } catch {
            guard !Task.isCancelled else { return }
            let description = error.localizedDescription
            loadError = description.hasSuffix(".") ? description : description + "."
        }
    }
}

import SwiftUI

/// Sends arbitrary bytes to an arbitrary characteristic.
///
/// The Pavlok 2/3 payload layout is reconstructed from field names, not from
/// a capture (see `LegacyDeviceController`). Rather than guess again in
/// source and rebuild each time, this screen makes the guess adjustable at
/// runtime with the hardware in hand: pick a characteristic from what the
/// device actually exposes, type the bytes, send, and read the result in the
/// Bluetooth log.
///
/// Not reachable from any normal flow — Diagnostics only.
struct ProtocolLabView: View {
    let viewModel: DeviceControlViewModel
    let gatt: [GATTCharacteristicDump]

    @State private var selectedID: String = ""
    /// Whether the hex field still holds a prefilled value, so typing isn't
    /// overwritten when the selection is re-applied.
    @State private var isHexUserEdited = false
    @State private var hexInput: String = "01 14"
    @State private var result: String?
    @State private var isSending = false

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
            Section("Characteristic") {
                if writable.isEmpty {
                    Text("No writable characteristics discovered. Connect a device and reload Diagnostics.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Target", selection: $selectedID) {
                        Text("Choose…").tag("")
                        ForEach(writable) { characteristic in
                            Text("\(characteristic.serviceUUID) / \(characteristic.uuid)")
                                .tag(characteristic.id)
                        }
                    }
                    .accessibilityIdentifier("protocolLabTargetPicker")
                    // Prefill with what the characteristic currently holds.
                    // A wrong-length write is rejected outright, so starting
                    // from the device's own value and changing one byte is
                    // both the safest and the fastest way to find a layout.
                    .onChange(of: selectedID) { _, _ in
                        guard !isHexUserEdited, let value = selected?.value, !value.isEmpty else { return }
                        hexInput = value
                    }
                    if let selected {
                        LabeledContent("Properties", value: selected.properties.joined(separator: ", "))
                            .font(.footnote)
                        if let value = selected.value {
                            LabeledContent("Current value", value: value.isEmpty ? "(empty)" : value)
                                .font(.footnote.monospaced())
                        }
                    }
                }
            }

            Section {
                TextField("Bytes, e.g. 01 14", text: $hexInput)
                    .font(.body.monospaced())
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("protocolLabHexField")
                    .onChange(of: hexInput) { _, _ in isHexUserEdited = true }
                if let parsedBytes {
                    let expected = selected?.value.map { $0.split(separator: " ").count }
                    let mismatch = expected.map { $0 != parsedBytes.count && $0 > 0 } ?? false
                    LabeledContent(
                        "Will send",
                        value: "\(parsedBytes.count) byte\(parsedBytes.count == 1 ? "" : "s")"
                            + (mismatch ? " — device holds \(expected ?? 0)" : "")
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not valid hex.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Payload")
            } footer: {
                Text("Hex, whitespace optional. The current guess for a stimulus is repetitions "
                    + "then intensity — 01 14 is one pulse at 20%.")
            }

            Section {
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Text("Send")
                    }
                }
                .disabled(selected == nil || parsedBytes == nil || isSending)
                .accessibilityIdentifier("protocolLabSendButton")

                if let result {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(result.hasPrefix("Sent") ? .green : .red)
                }
            } footer: {
                Text("Start with a characteristic you believe is Beep. An unknown characteristic could be the zap output.")
            }

            Section {
                NavigationLink("Bluetooth log") { BluetoothLogView() }
            }
        }
        .navigationTitle("Protocol lab")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("protocolLabScreen")
    }

    private func send() async {
        guard let selected, let bytes = parsedBytes else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await viewModel.writeRaw(
                Data(bytes),
                characteristicUUID: selected.uuid,
                serviceUUID: selected.serviceUUID
            )
            result = "Sent to \(selected.uuid)."
        } catch {
            result = error.localizedDescription
        }
    }

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
}

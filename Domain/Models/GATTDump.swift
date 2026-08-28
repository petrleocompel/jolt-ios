import Foundation

/// One characteristic as the connected device actually reports it.
///
/// Lives in `Domain` rather than `BLE` so `DeviceRepository` can expose a
/// GATT dump without dragging CoreBluetooth types across the layer boundary
/// — the UUIDs and property names are plain strings by the time they get
/// here.
struct GATTCharacteristicDump: Identifiable, Equatable, Codable {
    var id: String { "\(serviceUUID)/\(uuid)" }
    var serviceUUID: String
    var uuid: String
    var properties: [String]

    var isWritable: Bool {
        properties.contains("write") || properties.contains("writeNoResp")
    }
}

extension Array where Element == GATTCharacteristicDump {
    /// Human-readable dump, grouped by service — what gets shared out of the
    /// diagnostics screen.
    var transcript: String {
        Dictionary(grouping: self, by: \.serviceUUID)
            .sorted { $0.key < $1.key }
            .map { service, characteristics in
                let rows = characteristics
                    .sorted { $0.uuid < $1.uuid }
                    .map { "  \($0.uuid)  [\($0.properties.joined(separator: ", "))]" }
                    .joined(separator: "\n")
                return "Service \(service)\n\(rows)"
            }
            .joined(separator: "\n\n")
    }
}

import Foundation

enum DeviceConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case failed(String)
}

struct DeviceInfo: Codable, Equatable {
    var modelNumber: String?
    var serialNumber: String?
    var firmwareRevision: String?
    var hardwareRevision: String?
    var softwareRevision: String?
    var manufacturer: String?
    var batteryLevelPercent: Int?
}

/// A paired or discovered Pavlok device. `peripheralIdentifier` is CoreBluetooth's
/// `CBPeripheral.identifier` (UUID), stable per-device on a given iPhone.
struct PavlokDevice: Identifiable, Codable, Equatable {
    var id: UUID { peripheralIdentifier }
    var peripheralIdentifier: UUID
    var name: String
    var family: DeviceFamily
    var info: DeviceInfo
    var lastConnectedAt: Date?
    /// Signal strength when found by a scan, in dBm. `nil` for devices that
    /// came from anywhere else (already connected, restored, persisted).
    var rssi: Int?

    init(
        peripheralIdentifier: UUID,
        name: String,
        family: DeviceFamily,
        info: DeviceInfo = DeviceInfo(),
        lastConnectedAt: Date? = nil,
        rssi: Int? = nil
    ) {
        self.peripheralIdentifier = peripheralIdentifier
        self.name = name
        self.family = family
        self.info = info
        self.lastConnectedAt = lastConnectedAt
        self.rssi = rssi
    }
}

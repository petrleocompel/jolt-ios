import CoreBluetooth

/// Standard Bluetooth SIG services/characteristics — same on every device
/// family, confirmed against the Android binary's string table.
enum StandardGATT {
    static let deviceInformationService = CBUUID(string: "180A")
    static let modelNumber = CBUUID(string: "2A24")
    static let serialNumber = CBUUID(string: "2A25")
    static let firmwareRevision = CBUUID(string: "2A26")
    static let hardwareRevision = CBUUID(string: "2A27")
    static let softwareRevision = CBUUID(string: "2A28")
    static let manufacturerName = CBUUID(string: "2A29")

    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    static let clientCharacteristicConfig = CBUUID(string: "2902")
}

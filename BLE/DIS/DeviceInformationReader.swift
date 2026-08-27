import CoreBluetooth
import Foundation

/// Reads the standard Device Information + Battery services. Same on every
/// Pavlok family, so this is shared rather than duplicated per controller.
struct DeviceInformationReader {
    private let central: BluetoothCentralManager

    init(central: BluetoothCentralManager) {
        self.central = central
    }

    func read(from peripheral: CBPeripheral) async throws -> DeviceInfo {
        let service = StandardGATT.deviceInformationService
        var info = DeviceInfo()
        info.modelNumber = try? await readString(StandardGATT.modelNumber, service: service, on: peripheral)
        info.serialNumber = try? await readString(StandardGATT.serialNumber, service: service, on: peripheral)
        info.firmwareRevision = try? await readString(StandardGATT.firmwareRevision, service: service, on: peripheral)
        info.hardwareRevision = try? await readString(StandardGATT.hardwareRevision, service: service, on: peripheral)
        info.softwareRevision = try? await readString(StandardGATT.softwareRevision, service: service, on: peripheral)
        info.manufacturer = try? await readString(StandardGATT.manufacturerName, service: service, on: peripheral)
        if let batteryData = try? await central.read(StandardGATT.batteryLevel, from: StandardGATT.batteryService, on: peripheral),
           let level = batteryData.first {
            info.batteryLevelPercent = Int(level)
        }
        return info
    }

    private func readString(_ characteristic: CBUUID, service: CBUUID, on peripheral: CBPeripheral) async throws -> String? {
        let data = try await central.read(characteristic, from: service, on: peripheral)
        return String(data: data, encoding: .utf8)
    }
}

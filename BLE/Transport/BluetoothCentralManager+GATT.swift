import CoreBluetooth
import Foundation

/// Service and characteristic discovery, plus the two diagnostic sweeps the
/// app exposes: a full GATT dump and a notification capture.
///
/// Split out of `BluetoothCentralManager.swift` to keep that file readable —
/// these are the operations that exist to *learn* about a device rather than
/// to drive one, and they are what Diagnostics is built on.
extension BluetoothCentralManager {
    func dumpGATT(on peripheral: CBPeripheral, readingValues: Bool = false) async throws -> [GATTCharacteristicDump] {
        guard peripheral.state == .connected else { throw BluetoothError.bluetoothUnavailable }
        try await discoverServices(nil, on: peripheral)
        var dump: [GATTCharacteristicDump] = []
        for service in peripheral.services ?? [] {
            try? await discoverCharacteristics(nil, in: service, on: peripheral)
            for characteristic in service.characteristics ?? [] {
                var value: String?
                if readingValues, characteristic.properties.contains(.read) {
                    // A short timeout per characteristic: one unresponsive
                    // handle shouldn't stall a 40-characteristic sweep.
                    let data = try? await read(
                        characteristic.uuid,
                        from: service.uuid,
                        on: peripheral,
                        timeout: .seconds(3)
                    )
                    value = data.map { $0.map { String(format: "%02X", $0) }.joined(separator: " ") }
                }
                dump.append(GATTCharacteristicDump(
                    serviceUUID: service.uuid.uuidString,
                    uuid: characteristic.uuid.uuidString,
                    properties: characteristic.properties.labels,
                    value: value
                ))
            }
        }
        BLELog.info("GATT dump: \(dump.count) characteristics across \(peripheral.services?.count ?? 0) services")
        for entry in dump {
            let value = entry.value.map { " = \($0)" } ?? ""
            BLELog.debug("  \(entry.serviceUUID) / \(entry.uuid) [\(entry.properties.joined(separator: ","))]\(value)")
        }
        return dump
    }

    /// Subscribes to every notifying characteristic and logs whatever
    /// arrives.
    ///
    /// This is the closest thing to an HCI capture that runs on the phone.
    /// The parts of this protocol still missing are commands the app is
    /// supposed to *send*, and the device announces a good deal of what it
    /// does — so pressing the physical button, which fires a stimulus
    /// through firmware we cannot read, makes the device describe that event
    /// in its own encoding.
    ///
    /// Returns the number of characteristics successfully subscribed.
    @discardableResult
    func captureAllNotifications(on peripheral: CBPeripheral) async throws -> Int {
        guard peripheral.state == .connected else { throw BluetoothError.bluetoothUnavailable }
        stopNotificationCapture()
        try await discoverServices(nil, on: peripheral)

        var subscribed = 0
        for service in peripheral.services ?? [] {
            try? await discoverCharacteristics(nil, in: service, on: peripheral)
            for characteristic in service.characteristics ?? [] {
                guard characteristic.properties.contains(.notify)
                    || characteristic.properties.contains(.indicate) else { continue }
                guard let stream = try? await subscribe(characteristic.uuid, in: service.uuid, on: peripheral)
                else { continue }
                subscribed += 1
                let label = "\(service.uuid.uuidString)/\(characteristic.uuid.uuidString)"
                captureTasks.append(Task { @MainActor in
                    for await data in stream {
                        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
                        BLELog.info("EVENT \(label): \(hex.isEmpty ? "(empty)" : hex)")
                    }
                })
            }
        }
        BLELog.info("Listening on \(subscribed) notifying characteristic(s) — trigger something on the device now")
        return subscribed
    }

    func stopNotificationCapture() {
        guard !captureTasks.isEmpty else { return }
        captureTasks.forEach { $0.cancel() }
        captureTasks.removeAll()
        BLELog.info("Stopped listening for device events")
    }

    /// Finds the first characteristic from `candidates` that the device
    /// actually exposes and that accepts writes. Lets a controller carry a
    /// list of plausible UUIDs and let the hardware pick, instead of failing
    /// outright when one guess is wrong.
    func firstWritableCharacteristic(
        among candidates: [CBUUID],
        in serviceUUID: CBUUID,
        on peripheral: CBPeripheral
    ) async -> CBUUID? {
        try? await discoverServices([serviceUUID], on: peripheral)
        guard let service = peripheral.services?.first(where: { $0.uuid.matches(serviceUUID) }) else { return nil }
        try? await discoverCharacteristics(nil, in: service, on: peripheral)
        for candidate in candidates {
            if let match = service.characteristics?.first(where: { $0.uuid.matches(candidate) }),
               match.properties.contains(.write) || match.properties.contains(.writeWithoutResponse) {
                return candidate
            }
        }
        return nil
    }
}

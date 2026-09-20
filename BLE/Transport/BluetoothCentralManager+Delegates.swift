import CoreBluetooth
import Foundation

/// CoreBluetooth's delegate callbacks, funnelled onto the main actor and
/// matched up with the continuations the async API is parked on.
extension BluetoothCentralManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            BLELog.info("Bluetooth state: \(central.state.label)")
            stateContinuation?.yield(central.state)
            if central.state == .poweredOn {
                resumePoweredOnWaiters()
            } else if central.state == .unsupported || central.state == .unauthorized {
                failPoweredOnWaiters()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        Task { @MainActor in
            BLELog.info("Restoring \(peripherals.count) peripheral(s) from background relaunch")
            for peripheral in peripherals { peripheral.delegate = self }
            restoredPeripheralsContinuation?.yield(peripherals)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        Task { @MainActor in
            BLELog.debug("Discovered \(peripheral.identifier) name=\(peripheral.name ?? advertisedName ?? "nil") rssi=\(RSSI)")
            scanContinuation?.yield(DiscoveredPeripheral(
                peripheral: peripheral,
                advertisedName: advertisedName,
                rssi: RSSI.intValue,
                wasAlreadyConnected: false
            ))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectContinuations.removeValue(forKey: peripheral.identifier)?.resume()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            BLELog.error("Failed to connect \(peripheral.identifier): \(error?.localizedDescription ?? "unknown")")
            connectContinuations.removeValue(forKey: peripheral.identifier)?
                .resume(throwing: BluetoothError.connectFailed(error))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            BLELog.info("Disconnected \(peripheral.identifier): \(error?.localizedDescription ?? "clean")")
            notifyContinuations.removeValue(forKey: peripheral.identifier)?
                .values.flatMap(\.values).forEach { $0.finish() }
            // Anything still parked on this peripheral will never be
            // answered now — fail it rather than leak the task.
            failPendingOperations(for: peripheral.identifier)
            disconnectionContinuation?.yield((peripheralID: peripheral.identifier, error: error))
        }
    }

    private func failPendingOperations(for peripheralID: UUID) {
        readContinuations.removeValue(forKey: peripheralID)?.values
            .forEach { $0.resume(throwing: BluetoothError.bluetoothUnavailable) }
        writeContinuations.removeValue(forKey: peripheralID)?.values
            .forEach { $0.resume(throwing: BluetoothError.bluetoothUnavailable) }
        serviceDiscoveryWaiters.takeAll(for: peripheralID)
            .forEach { $0.resume(throwing: BluetoothError.bluetoothUnavailable) }
        characteristicDiscoveryWaiters.takeAll { $0.peripheralID == peripheralID }
            .forEach { $0.resume(throwing: BluetoothError.bluetoothUnavailable) }
    }
}

extension BluetoothCentralManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            // Everyone waiting on this peripheral is answered, not just the
            // most recent caller: discovery covers every service, so one
            // callback settles every outstanding wait. Resuming only one of
            // them is what used to strand the device-info read.
            let waiters = serviceDiscoveryWaiters.takeAll(for: peripheral.identifier)
            guard !waiters.isEmpty else { return }
            if let error {
                waiters.forEach { $0.resume(throwing: BluetoothError.readFailed(error)) }
            } else {
                let services = peripheral.services?.map(\.uuid.uuidString).joined(separator: ",") ?? "none"
                BLELog.debug("Services on \(peripheral.identifier): \(services)")
                waiters.forEach { $0.resume() }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            let scope = ServiceScope(
                peripheralID: peripheral.identifier,
                serviceUUID: service.uuid.canonicalString
            )
            let waiters = characteristicDiscoveryWaiters.takeAll(for: scope)
            guard !waiters.isEmpty else { return }
            if let error {
                waiters.forEach { $0.resume(throwing: BluetoothError.readFailed(error)) }
            } else {
                let found = service.characteristics?
                    .map { "\($0.uuid.uuidString)[\($0.properties.labels.joined(separator: "|"))]" }
                    .joined(separator: ",") ?? "none"
                BLELog.debug("Characteristics in \(service.uuid.uuidString): \(found)")
                waiters.forEach { $0.resume() }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            let data = characteristic.value ?? Data()
            if let continuation = readContinuations[peripheral.identifier]?.removeValue(forKey: characteristic.uuid.canonicalString) {
                if let error {
                    continuation.resume(throwing: BluetoothError.readFailed(error))
                } else {
                    continuation.resume(returning: data)
                }
                return
            }
            BLELog.debug("Notify \(characteristic.uuid.uuidString): \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
            let subscribers = notifyContinuations[peripheral.identifier]?[characteristic.uuid.canonicalString] ?? [:]
            for continuation in subscribers.values {
                continuation.yield(data)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard let continuation = writeContinuations[peripheral.identifier]?
                .removeValue(forKey: characteristic.uuid.canonicalString) else { return }
            if let error {
                continuation.resume(throwing: BluetoothError.writeFailed(error))
            } else {
                continuation.resume()
            }
        }
    }
}

import CoreBluetooth
import Foundation

/// Single owner of `CBCentralManager`/`CBPeripheral`. Everything else in
/// `BLE/` and `Data/` talks to hardware through this class rather than
/// touching CoreBluetooth directly, so the delegate-callback style stays in
/// one place and the rest of the codebase can use `async`/`await`.
@MainActor
final class BluetoothCentralManager: NSObject {
    enum BluetoothError: Error {
        case bluetoothUnavailable
        case connectFailed(Error?)
        case serviceNotFound(CBUUID)
        case characteristicNotFound(CBUUID)
        case writeFailed(Error?)
        case readFailed(Error?)
    }

    private lazy var central = CBCentralManager(delegate: self, queue: nil)

    private var scanContinuation: AsyncStream<CBPeripheral>.Continuation?
    private var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    /// Keyed by peripheral identifier, then characteristic UUID.
    private var notifyContinuations: [UUID: [CBUUID: AsyncStream<Data>.Continuation]] = [:]
    private var readContinuations: [UUID: [CBUUID: CheckedContinuation<Data, Error>]] = [:]
    private var writeContinuations: [UUID: [CBUUID: CheckedContinuation<Void, Error>]] = [:]

    var isPoweredOn: Bool { central.state == .poweredOn }

    func startScan(serviceUUIDs: [CBUUID]?) -> AsyncStream<CBPeripheral> {
        AsyncStream { continuation in
            self.scanContinuation = continuation
            guard self.central.state == .poweredOn else {
                continuation.finish()
                return
            }
            self.central.scanForPeripherals(withServices: serviceUUIDs, options: nil)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stopScan() }
            }
        }
    }

    func stopScan() {
        central.stopScan()
        scanContinuation?.finish()
        scanContinuation = nil
    }

    func connect(_ peripheral: CBPeripheral) async throws {
        guard central.state == .poweredOn else { throw BluetoothError.bluetoothUnavailable }
        peripheral.delegate = self
        try await withCheckedThrowingContinuation { continuation in
            connectContinuations[peripheral.identifier] = continuation
            central.connect(peripheral, options: nil)
        }
    }

    func disconnect(_ peripheral: CBPeripheral) {
        central.cancelPeripheralConnection(peripheral)
    }

    func write(_ data: Data, to characteristicUUID: CBUUID, serviceUUID: CBUUID, on peripheral: CBPeripheral) async throws {
        let characteristic = try await resolveCharacteristic(characteristicUUID, in: serviceUUID, on: peripheral)
        try await withCheckedThrowingContinuation { continuation in
            writeContinuations[peripheral.identifier, default: [:]][characteristicUUID] = continuation
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        }
    }

    func read(_ characteristicUUID: CBUUID, from serviceUUID: CBUUID, on peripheral: CBPeripheral) async throws -> Data {
        let characteristic = try await resolveCharacteristic(characteristicUUID, in: serviceUUID, on: peripheral)
        return try await withCheckedThrowingContinuation { continuation in
            readContinuations[peripheral.identifier, default: [:]][characteristicUUID] = continuation
            peripheral.readValue(for: characteristic)
        }
    }

    func subscribe(_ characteristicUUID: CBUUID, in serviceUUID: CBUUID, on peripheral: CBPeripheral) async throws -> AsyncStream<Data> {
        let characteristic = try await resolveCharacteristic(characteristicUUID, in: serviceUUID, on: peripheral)
        peripheral.setNotifyValue(true, for: characteristic)
        return AsyncStream { continuation in
            self.notifyContinuations[peripheral.identifier, default: [:]][characteristicUUID] = continuation
        }
    }

    private func resolveCharacteristic(
        _ characteristicUUID: CBUUID,
        in serviceUUID: CBUUID,
        on peripheral: CBPeripheral
    ) async throws -> CBCharacteristic {
        if let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }),
           let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) {
            return characteristic
        }

        try await discoverServices([serviceUUID], on: peripheral)
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            throw BluetoothError.serviceNotFound(serviceUUID)
        }
        try await discoverCharacteristics([characteristicUUID], in: service, on: peripheral)
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == characteristicUUID }) else {
            throw BluetoothError.characteristicNotFound(characteristicUUID)
        }
        return characteristic
    }

    private var discoverServicesContinuation: CheckedContinuation<Void, Error>?
    private var discoverCharacteristicsContinuation: CheckedContinuation<Void, Error>?

    private func discoverServices(_ uuids: [CBUUID], on peripheral: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { continuation in
            discoverServicesContinuation = continuation
            peripheral.discoverServices(uuids)
        }
    }

    private func discoverCharacteristics(_ uuids: [CBUUID], in service: CBService, on peripheral: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { continuation in
            discoverCharacteristicsContinuation = continuation
            peripheral.discoverCharacteristics(uuids, for: service)
        }
    }
}

extension BluetoothCentralManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {}

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            discoveredPeripherals[peripheral.identifier] = peripheral
            scanContinuation?.yield(peripheral)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            connectContinuations.removeValue(forKey: peripheral.identifier)?.resume()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectContinuations.removeValue(forKey: peripheral.identifier)?
                .resume(throwing: BluetoothError.connectFailed(error))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            notifyContinuations.removeValue(forKey: peripheral.identifier)?.values.forEach { $0.finish() }
        }
    }
}

extension BluetoothCentralManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                discoverServicesContinuation?.resume(throwing: BluetoothError.readFailed(error))
            } else {
                discoverServicesContinuation?.resume()
            }
            discoverServicesContinuation = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                discoverCharacteristicsContinuation?.resume(throwing: BluetoothError.readFailed(error))
            } else {
                discoverCharacteristicsContinuation?.resume()
            }
            discoverCharacteristicsContinuation = nil
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            let data = characteristic.value ?? Data()
            if let continuation = readContinuations[peripheral.identifier]?.removeValue(forKey: characteristic.uuid) {
                if let error {
                    continuation.resume(throwing: BluetoothError.readFailed(error))
                } else {
                    continuation.resume(returning: data)
                }
                return
            }
            notifyContinuations[peripheral.identifier]?[characteristic.uuid]?.yield(data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard let continuation = writeContinuations[peripheral.identifier]?.removeValue(forKey: characteristic.uuid) else { return }
            if let error {
                continuation.resume(throwing: BluetoothError.writeFailed(error))
            } else {
                continuation.resume()
            }
        }
    }
}

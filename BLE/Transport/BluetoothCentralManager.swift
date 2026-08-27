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

    /// Fixed identifier so iOS can relaunch us in the background and hand
    /// this exact `CBCentralManager` instance's state back via
    /// `willRestoreState`, instead of us losing track of the connection.
    static let restorationIdentifier = "cz.peelco.jolt.central"

    private lazy var central = CBCentralManager(
        delegate: self,
        queue: nil,
        options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier]
    )

    private var scanContinuation: AsyncStream<CBPeripheral>.Continuation?
    private var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]

    /// Keyed by peripheral identifier, then characteristic UUID.
    private var notifyContinuations: [UUID: [CBUUID: AsyncStream<Data>.Continuation]] = [:]
    private var readContinuations: [UUID: [CBUUID: CheckedContinuation<Data, Error>]] = [:]
    private var writeContinuations: [UUID: [CBUUID: CheckedContinuation<Void, Error>]] = [:]

    private var stateContinuation: AsyncStream<CBManagerState>.Continuation?
    private var disconnectionContinuation: AsyncStream<(peripheralID: UUID, error: Error?)>.Continuation?
    private var restoredPeripheralsContinuation: AsyncStream<[CBPeripheral]>.Continuation?

    var isPoweredOn: Bool { central.state == .poweredOn }

    /// Fires on every Bluetooth power/authorization change. Subscribers
    /// should react to `.poweredOff` (surface an error, clear connection
    /// state) and `.poweredOn` (retry a pending reconnect).
    private(set) lazy var stateUpdates: AsyncStream<CBManagerState> = AsyncStream { continuation in
        self.stateContinuation = continuation
        continuation.yield(self.central.state)
    }

    /// Fires when a peripheral disconnects, expectedly or not. `error` is
    /// non-nil for an unexpected drop (out of range, powered off, crashed) —
    /// callers use that to decide whether to auto-reconnect.
    private(set) lazy var disconnections: AsyncStream<(peripheralID: UUID, error: Error?)> = AsyncStream { continuation in
        self.disconnectionContinuation = continuation
    }

    /// Fires once per cold launch when iOS relaunches us in the background
    /// on behalf of a restored `CBCentralManager` session (see
    /// `CBCentralManagerOptionRestoreIdentifierKey`). Peripherals here are
    /// already connected or connecting — callers should adopt them rather
    /// than calling `connect(_:)` again.
    private(set) lazy var restoredPeripherals: AsyncStream<[CBPeripheral]> = AsyncStream { continuation in
        self.restoredPeripheralsContinuation = continuation
    }

    /// Looks up an already-known (previously connected or bonded)
    /// peripheral by identifier without scanning — the right way to
    /// reconnect to a device you've paired before.
    func retrieveKnownPeripheral(_ identifier: UUID) -> CBPeripheral? {
        central.retrievePeripherals(withIdentifiers: [identifier]).first
    }

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
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            stateContinuation?.yield(central.state)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        Task { @MainActor in
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
            disconnectionContinuation?.yield((peripheralID: peripheral.identifier, error: error))
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

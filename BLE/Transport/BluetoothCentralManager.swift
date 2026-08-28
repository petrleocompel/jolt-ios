import CoreBluetooth
import Foundation

/// One peripheral seen during a scan, plus the bits of the advertisement we
/// care about. `peripheral.name` alone is not enough: a bonded device that
/// iOS is already connected to often advertises nothing, and a device that
/// *is* advertising may only carry its name in the advertisement payload
/// (`CBAdvertisementDataLocalNameKey`) before the GAP name has been read.
struct DiscoveredPeripheral {
    var peripheral: CBPeripheral
    var advertisedName: String?
    var rssi: Int?
    /// True when this came from `retrieveConnectedPeripherals` rather than an
    /// advertisement — i.e. the phone was already connected to it.
    var wasAlreadyConnected: Bool

    /// Best available name. Falls back through GAP name → advertised local
    /// name → nothing.
    var displayName: String? {
        peripheral.name ?? advertisedName
    }
}

/// Single owner of `CBCentralManager`/`CBPeripheral`. Everything else in
/// `BLE/` and `Data/` talks to hardware through this class rather than
/// touching CoreBluetooth directly, so the delegate-callback style stays in
/// one place and the rest of the codebase can use `async`/`await`.
@MainActor
final class BluetoothCentralManager: NSObject {
    enum BluetoothError: LocalizedError {
        case bluetoothUnavailable
        case poweredOnTimeout
        case connectFailed(Error?)
        case serviceNotFound(CBUUID)
        case characteristicNotFound(CBUUID)
        /// The characteristic exists but declares neither `write` nor
        /// `writeWithoutResponse`. Writing to it is a silent no-op in
        /// CoreBluetooth, so we refuse loudly instead.
        case characteristicNotWritable(CBUUID)
        case writeFailed(Error?)
        case readFailed(Error?)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .bluetoothUnavailable: return "Bluetooth is unavailable."
            case .poweredOnTimeout: return "Bluetooth did not become ready in time."
            case .connectFailed(let error): return "Connection failed: \(error?.localizedDescription ?? "unknown reason")."
            case .serviceNotFound(let uuid): return "Service \(uuid.uuidString) not found on this device."
            case .characteristicNotFound(let uuid): return "Characteristic \(uuid.uuidString) not found on this device."
            case .characteristicNotWritable(let uuid): return "Characteristic \(uuid.uuidString) does not accept writes."
            case .writeFailed(let error): return "Write failed: \(error?.localizedDescription ?? "unknown reason")."
            case .readFailed(let error): return "Read failed: \(error?.localizedDescription ?? "unknown reason")."
            case .timedOut(let what): return "Timed out: \(what)."
            }
        }
    }

    /// Fixed identifier so iOS can relaunch us in the background and hand
    /// this exact `CBCentralManager` instance's state back via
    /// `willRestoreState`, instead of us losing track of the connection.
    static let restorationIdentifier = "cz.peelco.jolt.central"

    /// Services we ask `retrieveConnectedPeripherals` about. A Pavlok that
    /// iOS is already connected to will match at least one of these; other
    /// people's headphones may match too, which is harmless because callers
    /// filter by device name afterwards.
    static let knownServiceUUIDs: [CBUUID] = [
        LegacyGATT.service,
        SCMaxGATT.controlPointsService,
        StandardGATT.deviceInformationService,
        StandardGATT.batteryService
    ]

    private var central: CBCentralManager!

    private var scanContinuation: AsyncStream<DiscoveredPeripheral>.Continuation?
    private var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    /// Keyed by peripheral identifier, then by the characteristic's
    /// *canonical* UUID string. The key used when starting an operation
    /// comes from our own constants; the key used to resolve it comes from
    /// the peripheral, which reports Bluetooth-base UUIDs in 16-bit short
    /// form. Canonicalising both ends means the two agree regardless of
    /// which form each was written in — an unresolvable key here would park
    /// a write forever with no error. See `CBUUID+Canonical.swift`.
    private var notifyContinuations: [UUID: [String: AsyncStream<Data>.Continuation]] = [:]
    private var readContinuations: [UUID: [String: CheckedContinuation<Data, Error>]] = [:]
    private var writeContinuations: [UUID: [String: CheckedContinuation<Void, Error>]] = [:]

    /// Keyed by peripheral, so two peripherals discovering at once can't
    /// steal each other's completion (the previous single-slot version
    /// dropped one of them and hung forever).
    private var discoverServicesContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var discoverCharacteristicsContinuations: [UUID: [String: CheckedContinuation<Void, Error>]] = [:]

    private var stateContinuation: AsyncStream<CBManagerState>.Continuation?
    private var disconnectionContinuation: AsyncStream<(peripheralID: UUID, error: Error?)>.Continuation?
    private var restoredPeripheralsContinuation: AsyncStream<[CBPeripheral]>.Continuation?
    private var poweredOnWaiters: [CheckedContinuation<Void, Error>] = []

    override init() {
        super.init()
        // Created eagerly rather than lazily: `CBCentralManager` reports
        // `.unknown` for a short window after construction, and a scan
        // started in that window silently returns nothing. Building it up
        // front means the state machine is usually settled by the time the
        // first scan is requested, and `waitUntilPoweredOn()` covers the rest.
        central = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Self.restorationIdentifier]
        )
        BLELog.info("Central manager created")
    }

    var isPoweredOn: Bool { central.state == .poweredOn }
    var state: CBManagerState { central.state }

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

    /// Suspends until Bluetooth is actually usable. Scanning or connecting
    /// before this resolves is the single most common reason a device
    /// "isn't found" right after launch.
    func waitUntilPoweredOn(timeout: Duration = .seconds(5)) async throws {
        if central.state == .poweredOn { return }
        if central.state == .unsupported || central.state == .unauthorized {
            throw BluetoothError.bluetoothUnavailable
        }
        BLELog.debug("Waiting for Bluetooth to power on (state: \(central.state.label))")
        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.failPoweredOnWaiters()
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            poweredOnWaiters.append(continuation)
        }
    }

    private func failPoweredOnWaiters() {
        let waiters = poweredOnWaiters
        poweredOnWaiters.removeAll()
        for waiter in waiters { waiter.resume(throwing: BluetoothError.poweredOnTimeout) }
    }

    private func resumePoweredOnWaiters() {
        let waiters = poweredOnWaiters
        poweredOnWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    /// Looks up an already-known (previously connected or bonded)
    /// peripheral by identifier without scanning — the right way to
    /// reconnect to a device you've paired before.
    func retrieveKnownPeripheral(_ identifier: UUID) -> CBPeripheral? {
        central.retrievePeripherals(withIdentifiers: [identifier]).first
    }

    /// Peripherals iOS is *already* connected to. These never appear in a
    /// scan — CoreBluetooth only reports advertisements, and a connected
    /// device has stopped advertising — so they have to be pulled in
    /// separately or a device paired at the system level looks missing.
    func retrieveSystemConnectedPeripherals() -> [CBPeripheral] {
        central.retrieveConnectedPeripherals(withServices: Self.knownServiceUUIDs)
    }

    /// Starts a scan and yields everything found. `seedIdentifiers` are
    /// previously-paired peripherals to surface immediately without waiting
    /// for an advertisement.
    func startScan(serviceUUIDs: [CBUUID]?, seedIdentifiers: [UUID] = []) -> AsyncStream<DiscoveredPeripheral> {
        AsyncStream { continuation in
            self.scanContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.stopScan() }
            }

            Task { @MainActor in
                do {
                    try await self.waitUntilPoweredOn()
                } catch {
                    BLELog.error("Scan aborted: \(error.localizedDescription)")
                    continuation.finish()
                    return
                }

                // Seed before advertisements so an already-connected or
                // previously-bonded device shows up on the first frame.
                for peripheral in self.central.retrievePeripherals(withIdentifiers: seedIdentifiers) {
                    BLELog.info("Seeded known peripheral \(peripheral.identifier) name=\(peripheral.name ?? "nil")")
                    continuation.yield(DiscoveredPeripheral(
                        peripheral: peripheral, advertisedName: nil, rssi: nil, wasAlreadyConnected: false
                    ))
                }
                for peripheral in self.retrieveSystemConnectedPeripherals() {
                    BLELog.info("Seeded system-connected peripheral \(peripheral.identifier) name=\(peripheral.name ?? "nil")")
                    continuation.yield(DiscoveredPeripheral(
                        peripheral: peripheral, advertisedName: nil, rssi: nil, wasAlreadyConnected: true
                    ))
                }

                BLELog.info("Scanning for services=\(serviceUUIDs?.map(\.uuidString).joined(separator: ",") ?? "any")")
                // `allowDuplicates: false` — we de-duplicate by identifier
                // upstream anyway, and duplicates burn battery.
                self.central.scanForPeripherals(
                    withServices: serviceUUIDs,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
                )
            }
        }
    }

    func stopScan() {
        if central.isScanning {
            central.stopScan()
            BLELog.info("Scan stopped")
        }
        scanContinuation?.finish()
        scanContinuation = nil
    }

    func connect(_ peripheral: CBPeripheral, timeout: Duration = .seconds(15)) async throws {
        try await waitUntilPoweredOn()
        peripheral.delegate = self
        BLELog.info("Connecting to \(peripheral.identifier) (\(peripheral.name ?? "unnamed"))")
        try await withTimeout(timeout, description: "connect to \(peripheral.identifier)") {
            try await withCheckedThrowingContinuation { continuation in
                self.connectContinuations[peripheral.identifier] = continuation
                self.central.connect(peripheral, options: nil)
            }
        } onTimeout: { [weak self] in
            guard let self else { return }
            central.cancelPeripheralConnection(peripheral)
            connectContinuations.removeValue(forKey: peripheral.identifier)?
                .resume(throwing: BluetoothError.timedOut("connect"))
        }
        BLELog.info("Connected to \(peripheral.identifier)")
    }

    func disconnect(_ peripheral: CBPeripheral) {
        BLELog.info("Disconnecting \(peripheral.identifier)")
        central.cancelPeripheralConnection(peripheral)
    }

    /// Writes and, for characteristics that support it, waits for the
    /// device's acknowledgement.
    ///
    /// The write *type* is chosen from the characteristic's declared
    /// properties rather than hardcoded. This matters: CoreBluetooth
    /// silently discards a `.withResponse` write to a characteristic that
    /// only supports write-without-response — no error, no callback, no
    /// notification to the device. That failure mode is invisible unless you
    /// check the properties first, which is why it is done here for every
    /// write rather than at the call sites.
    func write(
        _ data: Data,
        to characteristicUUID: CBUUID,
        serviceUUID: CBUUID,
        on peripheral: CBPeripheral,
        timeout: Duration = .seconds(10)
    ) async throws {
        guard peripheral.state == .connected else {
            BLELog.error("Write to \(characteristicUUID.uuidString) skipped — peripheral not connected (state: \(peripheral.state.label))")
            throw BluetoothError.bluetoothUnavailable
        }
        let characteristic = try await resolveCharacteristic(characteristicUUID, in: serviceUUID, on: peripheral)
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")

        if characteristic.properties.contains(.write) {
            BLELog.info("Write (with response) \(hex) → \(characteristicUUID.uuidString)")
            try await withTimeout(timeout, description: "write to \(characteristicUUID.uuidString)") {
                try await withCheckedThrowingContinuation { continuation in
                    self.writeContinuations[peripheral.identifier, default: [:]][characteristicUUID.canonicalString] = continuation
                    peripheral.writeValue(data, for: characteristic, type: .withResponse)
                }
            } onTimeout: { [weak self] in
                self?.writeContinuations[peripheral.identifier]?.removeValue(forKey: characteristicUUID.canonicalString)?
                    .resume(throwing: BluetoothError.timedOut("write to \(characteristicUUID.uuidString)"))
            }
            BLELog.info("Write acknowledged by \(characteristicUUID.uuidString)")
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            BLELog.info("Write (no response) \(hex) → \(characteristicUUID.uuidString)")
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        } else {
            BLELog.error("Characteristic \(characteristicUUID.uuidString) is not writable (properties: \(characteristic.properties.labels.joined(separator: ",")))")
            throw BluetoothError.characteristicNotWritable(characteristicUUID)
        }
    }

    func read(
        _ characteristicUUID: CBUUID,
        from serviceUUID: CBUUID,
        on peripheral: CBPeripheral,
        timeout: Duration = .seconds(10)
    ) async throws -> Data {
        guard peripheral.state == .connected else { throw BluetoothError.bluetoothUnavailable }
        let characteristic = try await resolveCharacteristic(characteristicUUID, in: serviceUUID, on: peripheral)
        return try await withTimeout(timeout, description: "read \(characteristicUUID.uuidString)") {
            try await withCheckedThrowingContinuation { continuation in
                self.readContinuations[peripheral.identifier, default: [:]][characteristicUUID.canonicalString] = continuation
                peripheral.readValue(for: characteristic)
            }
        } onTimeout: { [weak self] in
            self?.readContinuations[peripheral.identifier]?.removeValue(forKey: characteristicUUID.canonicalString)?
                .resume(throwing: BluetoothError.timedOut("read \(characteristicUUID.uuidString)"))
        }
    }

    func subscribe(_ characteristicUUID: CBUUID, in serviceUUID: CBUUID, on peripheral: CBPeripheral) async throws -> AsyncStream<Data> {
        let characteristic = try await resolveCharacteristic(characteristicUUID, in: serviceUUID, on: peripheral)
        guard characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) else {
            throw BluetoothError.characteristicNotFound(characteristicUUID)
        }
        peripheral.setNotifyValue(true, for: characteristic)
        BLELog.info("Subscribed to \(characteristicUUID.uuidString)")
        return AsyncStream { continuation in
            self.notifyContinuations[peripheral.identifier, default: [:]][characteristicUUID.canonicalString] = continuation
        }
    }

    /// Discovers every service and characteristic on the peripheral. Used by
    /// the diagnostics screen: with the Pavlok wire protocol only partly
    /// recovered, seeing the device's real GATT table is the fastest way to
    /// tell a wrong UUID from a wrong payload.
    func dumpGATT(on peripheral: CBPeripheral) async throws -> [GATTCharacteristicDump] {
        guard peripheral.state == .connected else { throw BluetoothError.bluetoothUnavailable }
        try await discoverServices(nil, on: peripheral)
        var dump: [GATTCharacteristicDump] = []
        for service in peripheral.services ?? [] {
            try? await discoverCharacteristics(nil, in: service, on: peripheral)
            for characteristic in service.characteristics ?? [] {
                dump.append(GATTCharacteristicDump(
                    serviceUUID: service.uuid.uuidString,
                    uuid: characteristic.uuid.uuidString,
                    properties: characteristic.properties.labels
                ))
            }
        }
        BLELog.info("GATT dump: \(dump.count) characteristics across \(peripheral.services?.count ?? 0) services")
        for entry in dump {
            BLELog.debug("  \(entry.serviceUUID) / \(entry.uuid) [\(entry.properties.joined(separator: ","))]")
        }
        return dump
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

    private func resolveCharacteristic(
        _ characteristicUUID: CBUUID,
        in serviceUUID: CBUUID,
        on peripheral: CBPeripheral
    ) async throws -> CBCharacteristic {
        if let service = peripheral.services?.first(where: { $0.uuid.matches(serviceUUID) }),
           let characteristic = service.characteristics?.first(where: { $0.uuid.matches(characteristicUUID) }) {
            return characteristic
        }

        try await discoverServices([serviceUUID], on: peripheral)
        guard let service = peripheral.services?.first(where: { $0.uuid.matches(serviceUUID) }) else {
            BLELog.error("Service \(serviceUUID.uuidString) not found. Present: \(peripheral.services?.map(\.uuid.uuidString).joined(separator: ",") ?? "none")")
            throw BluetoothError.serviceNotFound(serviceUUID)
        }
        // Discover *all* characteristics rather than only the one asked for:
        // the extra ones cost nothing and make the "what's actually on this
        // device" log line useful when a UUID guess turns out wrong.
        try await discoverCharacteristics(nil, in: service, on: peripheral)
        guard let characteristic = service.characteristics?.first(where: { $0.uuid.matches(characteristicUUID) }) else {
            BLELog.error("Characteristic \(characteristicUUID.uuidString) not found in \(serviceUUID.uuidString). Present: \(service.characteristics?.map(\.uuid.uuidString).joined(separator: ",") ?? "none")")
            throw BluetoothError.characteristicNotFound(characteristicUUID)
        }
        return characteristic
    }

    private func discoverServices(_ uuids: [CBUUID]?, on peripheral: CBPeripheral, timeout: Duration = .seconds(10)) async throws {
        try await withTimeout(timeout, description: "discover services") {
            try await withCheckedThrowingContinuation { continuation in
                self.discoverServicesContinuations[peripheral.identifier] = continuation
                peripheral.discoverServices(uuids)
            }
        } onTimeout: { [weak self] in
            self?.discoverServicesContinuations.removeValue(forKey: peripheral.identifier)?
                .resume(throwing: BluetoothError.timedOut("discover services"))
        }
    }

    private func discoverCharacteristics(
        _ uuids: [CBUUID]?,
        in service: CBService,
        on peripheral: CBPeripheral,
        timeout: Duration = .seconds(10)
    ) async throws {
        try await withTimeout(timeout, description: "discover characteristics") {
            try await withCheckedThrowingContinuation { continuation in
                self.discoverCharacteristicsContinuations[peripheral.identifier, default: [:]][service.uuid.canonicalString] = continuation
                peripheral.discoverCharacteristics(uuids, for: service)
            }
        } onTimeout: { [weak self] in
            self?.discoverCharacteristicsContinuations[peripheral.identifier]?.removeValue(forKey: service.uuid.canonicalString)?
                .resume(throwing: BluetoothError.timedOut("discover characteristics"))
        }
    }

    /// Races `operation` against a timer. `onTimeout` is responsible for
    /// resuming whichever continuation `operation` is parked on — without it
    /// a lost CoreBluetooth callback leaks the task forever, which is
    /// exactly how a tap on "Zap" can produce no result and no error.
    private func withTimeout(
        _ duration: Duration,
        description: String,
        operation: @escaping () async throws -> Void,
        onTimeout: @escaping @MainActor () -> Void
    ) async throws {
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            BLELog.error("Timed out: \(description)")
            onTimeout()
        }
        defer { timeoutTask.cancel() }
        try await operation()
    }

    private func withTimeout<T>(
        _ duration: Duration,
        description: String,
        operation: @escaping () async throws -> T,
        onTimeout: @escaping @MainActor () -> Void
    ) async throws -> T {
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            BLELog.error("Timed out: \(description)")
            onTimeout()
        }
        defer { timeoutTask.cancel() }
        return try await operation()
    }
}

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
            notifyContinuations.removeValue(forKey: peripheral.identifier)?.values.forEach { $0.finish() }
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
        discoverServicesContinuations.removeValue(forKey: peripheralID)?
            .resume(throwing: BluetoothError.bluetoothUnavailable)
        discoverCharacteristicsContinuations.removeValue(forKey: peripheralID)?.values
            .forEach { $0.resume(throwing: BluetoothError.bluetoothUnavailable) }
    }
}

extension BluetoothCentralManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let continuation = discoverServicesContinuations.removeValue(forKey: peripheral.identifier) else { return }
            if let error {
                continuation.resume(throwing: BluetoothError.readFailed(error))
            } else {
                BLELog.debug("Services on \(peripheral.identifier): \(peripheral.services?.map(\.uuid.uuidString).joined(separator: ",") ?? "none")")
                continuation.resume()
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let continuation = discoverCharacteristicsContinuations[peripheral.identifier]?
                .removeValue(forKey: service.uuid.canonicalString) else { return }
            if let error {
                continuation.resume(throwing: BluetoothError.readFailed(error))
            } else {
                BLELog.debug("Characteristics in \(service.uuid.uuidString): \(service.characteristics?.map { "\($0.uuid.uuidString)[\($0.properties.labels.joined(separator: "|"))]" }.joined(separator: ",") ?? "none")")
                continuation.resume()
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
            notifyContinuations[peripheral.identifier]?[characteristic.uuid.canonicalString]?.yield(data)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard let continuation = writeContinuations[peripheral.identifier]?.removeValue(forKey: characteristic.uuid.canonicalString) else { return }
            if let error {
                continuation.resume(throwing: BluetoothError.writeFailed(error))
            } else {
                continuation.resume()
            }
        }
    }
}

// MARK: - Log-friendly descriptions

extension CBManagerState {
    var label: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unrecognised(\(rawValue))"
        }
    }
}

extension CBPeripheralState {
    var label: String {
        switch self {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unrecognised(\(rawValue))"
        }
    }
}

extension CBCharacteristicProperties {
    var labels: [String] {
        var labels: [String] = []
        if contains(.broadcast) { labels.append("broadcast") }
        if contains(.read) { labels.append("read") }
        if contains(.writeWithoutResponse) { labels.append("writeNoResp") }
        if contains(.write) { labels.append("write") }
        if contains(.notify) { labels.append("notify") }
        if contains(.indicate) { labels.append("indicate") }
        if contains(.authenticatedSignedWrites) { labels.append("signedWrite") }
        if contains(.extendedProperties) { labels.append("extended") }
        return labels
    }
}

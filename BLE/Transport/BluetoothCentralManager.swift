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
/// Members below are `internal` rather than `private` only because this type
/// is split across `BluetoothCentralManager+{GATT,Delegates,Descriptions}.swift`
/// and `private` in Swift is file-scoped. Nothing outside `BLE/Transport/`
/// should touch them.
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

    var central: CBCentralManager!

    var scanContinuation: AsyncStream<DiscoveredPeripheral>.Continuation?
    var connectContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]

    /// Keyed by peripheral identifier, then by the characteristic's
    /// *canonical* UUID string. The key used when starting an operation
    /// comes from our own constants; the key used to resolve it comes from
    /// the peripheral, which reports Bluetooth-base UUIDs in 16-bit short
    /// form. Canonicalising both ends means the two agree regardless of
    /// which form each was written in — an unresolvable key here would park
    /// a write forever with no error. See `CBUUID+Canonical.swift`.
    /// Notify subscribers, keyed peripheral → characteristic → subscriber.
    ///
    /// The innermost dictionary is why this is three levels deep: a single
    /// slot per characteristic meant the *second* subscriber replaced the
    /// first, silently. That is not hypothetical — opening the diagnostics
    /// capture screen re-subscribes to every notifying characteristic, which
    /// used to knock the poke trigger off the air with no error anywhere, and
    /// the trigger kept reporting itself as listening.
    var notifyContinuations: [UUID: [String: [UUID: AsyncStream<Data>.Continuation]]] = [:]
    var readContinuations: [UUID: [String: CheckedContinuation<Data, Error>]] = [:]
    var writeContinuations: [UUID: [String: CheckedContinuation<Void, Error>]] = [:]

    /// Keyed by peripheral, so two peripherals discovering at once can't
    /// steal each other's completion (the previous single-slot version
    /// dropped one of them and hung forever).
    var discoverServicesContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    var discoverCharacteristicsContinuations: [UUID: [String: CheckedContinuation<Void, Error>]] = [:]

    var stateContinuation: AsyncStream<CBManagerState>.Continuation?
    var disconnectionContinuation: AsyncStream<(peripheralID: UUID, error: Error?)>.Continuation?
    var restoredPeripheralsContinuation: AsyncStream<[CBPeripheral]>.Continuation?
    var poweredOnWaiters: [CheckedContinuation<Void, Error>] = []
    /// One per subscribed characteristic while `captureAllNotifications` is
    /// active.
    var captureTasks: [Task<Void, Never>] = []
    /// One per subscribed characteristic while `streamAllNotifications` is
    /// active — the structured feed the poke trigger consumes. Kept separate
    /// from `captureTasks` so the diagnostics capture screen and the trigger
    /// can run independently.
    var eventStreamTasks: [Task<Void, Never>] = []

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

    func failPoweredOnWaiters() {
        let waiters = poweredOnWaiters
        poweredOnWaiters.removeAll()
        for waiter in waiters { waiter.resume(throwing: BluetoothError.poweredOnTimeout) }
    }

    func resumePoweredOnWaiters() {
        let waiters = poweredOnWaiters
        poweredOnWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func connect(_ peripheral: CBPeripheral, timeout: Duration = .seconds(15)) async throws {
        try await waitUntilPoweredOn()
        peripheral.delegate = self
        BLELog.info("Connecting to \(peripheral.identifier) (\(peripheral.name ?? "unnamed"))")
        try await withTimeout(timeout, description: "connect to \(peripheral.identifier)") {
            try await withCheckedThrowingContinuation { continuation in
                // Only one connect can be pending per peripheral: the
                // dictionary holds a single slot, and `didConnect` resumes
                // exactly one waiter. Overwriting a live continuation strands
                // whoever was waiting on it — cancelling the enclosing task
                // does *not* resume a suspended continuation, so it leaks and
                // its timeout fires later against an already-connected
                // peripheral. Retire the previous one explicitly instead.
                if let stranded = self.connectContinuations.removeValue(forKey: peripheral.identifier) {
                    BLELog.debug("Superseding an in-flight connect to \(peripheral.identifier)")
                    stranded.resume(throwing: CancellationError())
                }
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
    ///
    /// - Parameter type: forces a write type instead of choosing one. Only the
    ///   Protocol lab passes it. A forced type the characteristic doesn't
    ///   declare is refused with `characteristicNotWritable` rather than sent,
    ///   for the same silent-discard reason as above.
    func write(
        _ data: Data,
        to characteristicUUID: CBUUID,
        serviceUUID: CBUUID,
        on peripheral: CBPeripheral,
        type: CBCharacteristicWriteType? = nil,
        timeout: Duration = .seconds(10)
    ) async throws {
        guard peripheral.state == .connected else {
            BLELog.error("Write to \(characteristicUUID.uuidString) skipped — peripheral not connected (state: \(peripheral.state.label))")
            throw BluetoothError.bluetoothUnavailable
        }
        let characteristic = try await resolveCharacteristic(characteristicUUID, in: serviceUUID, on: peripheral)
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")

        let resolvedType = Self.writeType(requested: type, properties: characteristic.properties)

        if resolvedType == .withResponse {
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
        } else if resolvedType == .withoutResponse {
            BLELog.info("Write (no response) \(hex) → \(characteristicUUID.uuidString)")
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        } else {
            let properties = characteristic.properties.labels.joined(separator: ",")
            let requested = type.map { $0 == .withResponse ? " with response" : " without response" } ?? ""
            BLELog.error("Characteristic \(characteristicUUID.uuidString) is not writable\(requested) (properties: \(properties))")
            throw BluetoothError.characteristicNotWritable(characteristicUUID)
        }
    }

    /// The write type `write` will actually use, or `nil` when the
    /// characteristic can't take the write at all. With nothing requested,
    /// with-response wins when both are declared: an acknowledgement is the
    /// only proof a stimulus write landed.
    nonisolated static func writeType(
        requested: CBCharacteristicWriteType?,
        properties: CBCharacteristicProperties
    ) -> CBCharacteristicWriteType? {
        let supportsWithResponse = properties.contains(.write)
        let supportsWithoutResponse = properties.contains(.writeWithoutResponse)
        switch requested {
        case .withResponse?:
            return supportsWithResponse ? .withResponse : nil
        case .withoutResponse?:
            return supportsWithoutResponse ? .withoutResponse : nil
        case nil:
            if supportsWithResponse { return .withResponse }
            return supportsWithoutResponse ? .withoutResponse : nil
        @unknown default:
            return nil
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
        let key = characteristicUUID.canonicalString
        let peripheralID = peripheral.identifier
        return AsyncStream { continuation in
            let token = UUID()
            self.notifyContinuations[peripheralID, default: [:]][key, default: [:]][token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.notifyContinuations[peripheralID]?[key]?.removeValue(forKey: token)
                }
            }
        }
    }

    /// Discovers every service and characteristic on the peripheral. Used by
    /// the diagnostics screen: with the Pavlok wire protocol only partly
    /// recovered, seeing the device's real GATT table is the fastest way to
    /// tell a wrong UUID from a wrong payload.
    /// - Parameter readingValues: also reads every readable characteristic.
    ///   Reads are non-destructive — no stimulus can fire from one — so this
    ///   is the safe way to work out which config characteristic is which:
    ///   the value a characteristic already holds usually gives it away.

    func resolveCharacteristic(
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
            let present = peripheral.services?.map(\.uuid.uuidString).joined(separator: ",") ?? "none"
            BLELog.error("Service \(serviceUUID.uuidString) not found. Present: \(present)")
            throw BluetoothError.serviceNotFound(serviceUUID)
        }
        // Discover *all* characteristics rather than only the one asked for:
        // the extra ones cost nothing and make the "what's actually on this
        // device" log line useful when a UUID guess turns out wrong.
        try await discoverCharacteristics(nil, in: service, on: peripheral)
        guard let characteristic = service.characteristics?.first(where: { $0.uuid.matches(characteristicUUID) }) else {
            let present = service.characteristics?.map(\.uuid.uuidString).joined(separator: ",") ?? "none"
            BLELog.error("Characteristic \(characteristicUUID.uuidString) not found in \(serviceUUID.uuidString). Present: \(present)")
            throw BluetoothError.characteristicNotFound(characteristicUUID)
        }
        return characteristic
    }

    func discoverServices(_ uuids: [CBUUID]?, on peripheral: CBPeripheral, timeout: Duration = .seconds(10)) async throws {
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

    func discoverCharacteristics(
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
}

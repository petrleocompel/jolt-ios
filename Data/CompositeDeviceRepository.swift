import CoreBluetooth
import Foundation

/// Default `DeviceRepository`. Owns the one `BluetoothCentralManager` and
/// dispatches per-family operations to `LegacyDeviceController` /
/// `SCMaxDeviceController` — everything above this layer (`Features/`) is
/// unaware CoreBluetooth or ESF exist.
///
/// Also owns connection *reliability*: remembers the last-paired device
/// (`PairedDeviceStore`), auto-reconnects on launch and whenever Bluetooth
/// powers back on, reacts to unexpected drops, and adopts peripherals
/// handed back after a background relaunch (`CBCentralManagerOptionRestoreIdentifierKey`).
@MainActor
final class CompositeDeviceRepository: DeviceRepository {
    private let central = BluetoothCentralManager()
    private lazy var legacy = LegacyDeviceController(central: central)
    private lazy var scMax = SCMaxDeviceController(central: central)
    private lazy var deviceInfoReader = DeviceInformationReader(central: central)
    private let store: PairedDeviceStore

    private var connectionStateContinuation: AsyncStream<DeviceConnectionState>.Continuation?
    private var connectedDeviceContinuation: AsyncStream<PavlokDevice?>.Continuation?

    private var connectedPeripheral: CBPeripheral?
    private var connectedFamily: DeviceFamily?
    private var didStart = false

    // Only touched on the main actor; `nonisolated(unsafe)` so `deinit`
    // (always nonisolated) can cancel them.
    nonisolated(unsafe) private var stateTask: Task<Void, Never>?
    nonisolated(unsafe) private var disconnectionTask: Task<Void, Never>?
    nonisolated(unsafe) private var restoreTask: Task<Void, Never>?
    nonisolated(unsafe) private var reconnectTask: Task<Void, Never>?

    init(store: PairedDeviceStore = PairedDeviceStore()) {
        self.store = store
    }

    deinit {
        stateTask?.cancel()
        disconnectionTask?.cancel()
        restoreTask?.cancel()
        reconnectTask?.cancel()
    }

    private(set) lazy var connectionState: AsyncStream<DeviceConnectionState> = AsyncStream { continuation in
        self.connectionStateContinuation = continuation
        self.startIfNeeded()
    }

    private(set) lazy var connectedDevice: AsyncStream<PavlokDevice?> = AsyncStream { continuation in
        self.connectedDeviceContinuation = continuation
        self.startIfNeeded()
    }

    /// Wires up event observation and kicks off an initial reconnect
    /// attempt. Deferred to first access of either stream (rather than
    /// `init`) so `connectionStateContinuation`/`connectedDeviceContinuation`
    /// are guaranteed to exist before anything tries to yield on them — see
    /// header note on `AsyncStream` buffering vs. subscriber timing.
    private func startIfNeeded() {
        guard !didStart else { return }
        didStart = true

        stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in central.stateUpdates {
                handlePowerStateChange(state)
            }
        }
        disconnectionTask = Task { [weak self] in
            guard let self else { return }
            for await event in central.disconnections {
                handleUnexpectedDisconnection(event)
            }
        }
        restoreTask = Task { [weak self] in
            guard let self else { return }
            for await peripherals in central.restoredPeripherals {
                adoptRestoredPeripherals(peripherals)
            }
        }
        Task { [weak self] in
            await self?.attemptAutoReconnect()
        }
    }

    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice> {
        connectionStateContinuation?.yield(.scanning)
        let peripherals = central.startScan(serviceUUIDs: nil)
        return AsyncStream { continuation in
            let task = Task {
                for await peripheral in peripherals {
                    guard let name = peripheral.name,
                          let family = Self.family(matching: name, in: families) else { continue }
                    continuation.yield(PavlokDevice(peripheralIdentifier: peripheral.identifier, name: name, family: family))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stopScan() {
        central.stopScan()
        connectionStateContinuation?.yield(.disconnected)
    }

    func connect(to device: PavlokDevice) async throws {
        reconnectTask?.cancel()
        connectionStateContinuation?.yield(.connecting)
        // Re-discovery is required: CoreBluetooth doesn't let us reconnect to
        // a CBPeripheral instance from a previous scan session by UUID alone
        // without `retrievePeripherals(withIdentifiers:)`, which needs the
        // central to already be powered on and have seen the identifier.
        guard central.isPoweredOn else {
            connectionStateContinuation?.yield(.failed("Bluetooth is off"))
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        let scan = central.startScan(serviceUUIDs: nil)
        var matched: CBPeripheral?
        for await peripheral in scan where peripheral.identifier == device.peripheralIdentifier {
            matched = peripheral
            break
        }
        central.stopScan()
        guard let peripheral = matched else {
            connectionStateContinuation?.yield(.failed("Device not found"))
            throw BluetoothCentralManager.BluetoothError.connectFailed(nil)
        }
        do {
            try await central.connect(peripheral)
            connectedPeripheral = peripheral
            connectedFamily = device.family
            store.save(peripheralIdentifier: peripheral.identifier, name: device.name, family: device.family)
            connectionStateContinuation?.yield(.connected)
            connectedDeviceContinuation?.yield(device)
        } catch {
            connectionStateContinuation?.yield(.failed("\(error)"))
            throw error
        }
    }

    func disconnect() async {
        reconnectTask?.cancel()
        if let peripheral = connectedPeripheral {
            central.disconnect(peripheral)
        }
        connectedPeripheral = nil
        connectedFamily = nil
        connectionStateContinuation?.yield(.disconnected)
        connectedDeviceContinuation?.yield(nil)
    }

    func forgetPairedDevice() async {
        reconnectTask?.cancel()
        if let peripheral = connectedPeripheral {
            central.disconnect(peripheral)
        }
        connectedPeripheral = nil
        connectedFamily = nil
        store.clear()
        connectionStateContinuation?.yield(.disconnected)
        connectedDeviceContinuation?.yield(nil)
    }

    func fire(_ stimulus: StimulusConfig) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.fire(stimulus, on: peripheral)
        case .shockClockMax:
            try await scMax.fire(stimulus, on: peripheral)
        }
    }

    func readDeviceInfo() async throws -> DeviceInfo {
        guard let peripheral = connectedPeripheral else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        return try await deviceInfoReader.read(from: peripheral)
    }

    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            let payload = Data([press.wireValue, config.action.wireValue])
            try await central.write(payload, to: LegacyGATT.buttonConfig, serviceUUID: LegacyGATT.service, on: peripheral)
        case .shockClockMax:
            throw SCMaxDeviceController.ControllerError.notImplemented(
                "Button config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }
    }

    func syncDeviceAlarm(_ alarm: Alarm) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.syncAlarm(alarm, on: peripheral)
        case .shockClockMax:
            try await scMax.syncAlarm(alarm, on: peripheral)
        }
    }

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.deleteAlarm(id, on: peripheral)
        case .shockClockMax:
            try await scMax.deleteAlarm(id, on: peripheral)
        }
    }

    private static func family(matching name: String, in families: Set<DeviceFamily>) -> DeviceFamily? {
        families.first { family in
            family.advertisedNamePrefixes.contains { name.localizedCaseInsensitiveContains($0) }
        }
    }
}

// MARK: - Reliability: reconnect, power state, background restoration

extension CompositeDeviceRepository {
    private func attemptAutoReconnect() async {
        guard let record = store.load() else { return }
        guard central.isPoweredOn else { return } // retried from handlePowerStateChange once it powers on
        guard let peripheral = central.retrieveKnownPeripheral(record.peripheralIdentifier) else {
            connectionStateContinuation?.yield(.failed("Paired device not found"))
            return
        }
        scheduleReconnect(to: peripheral, family: record.family, name: record.name)
    }

    private func scheduleReconnect(to peripheral: CBPeripheral, family: DeviceFamily, name: String) {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            connectionStateContinuation?.yield(.connecting)
            do {
                try await central.connect(peripheral)
                guard !Task.isCancelled else { return }
                connectedPeripheral = peripheral
                connectedFamily = family
                store.save(peripheralIdentifier: peripheral.identifier, name: name, family: family)
                connectionStateContinuation?.yield(.connected)
                connectedDeviceContinuation?.yield(PavlokDevice(peripheralIdentifier: peripheral.identifier, name: name, family: family))
            } catch {
                guard !Task.isCancelled else { return }
                connectionStateContinuation?.yield(.failed("\(error)"))
            }
        }
    }

    private func handlePowerStateChange(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            if connectedPeripheral == nil {
                Task { await attemptAutoReconnect() }
            }
        case .poweredOff:
            reconnectTask?.cancel()
            connectedPeripheral = nil
            connectionStateContinuation?.yield(.failed("Bluetooth is off"))
            connectedDeviceContinuation?.yield(nil)
        case .unauthorized:
            connectionStateContinuation?.yield(.failed("Bluetooth permission denied"))
        case .unsupported:
            connectionStateContinuation?.yield(.failed("Bluetooth not supported on this device"))
        case .resetting, .unknown:
            break
        @unknown default:
            break
        }
    }

    /// An unexpected drop (out of range, device powered off, crashed).
    /// Manual `disconnect()`/`forgetPairedDevice()` already nil out
    /// `connectedPeripheral` before CoreBluetooth's callback arrives, so by
    /// the time this runs for one of those the identifier check below no
    /// longer matches and nothing happens — no separate "was this manual"
    /// flag needed.
    private func handleUnexpectedDisconnection(_ event: (peripheralID: UUID, error: Error?)) {
        guard let peripheral = connectedPeripheral, let family = connectedFamily,
              peripheral.identifier == event.peripheralID else { return }
        connectedPeripheral = nil
        connectionStateContinuation?.yield(.disconnected)
        connectedDeviceContinuation?.yield(nil)

        let name = store.load()?.name ?? family.displayName
        scheduleReconnect(to: peripheral, family: family, name: name)
    }

    private func adoptRestoredPeripherals(_ peripherals: [CBPeripheral]) {
        guard let peripheral = peripherals.first,
              let record = store.load(),
              record.peripheralIdentifier == peripheral.identifier else { return }
        connectedPeripheral = peripheral
        connectedFamily = record.family
        connectionStateContinuation?.yield(.connected)
        let device = PavlokDevice(peripheralIdentifier: peripheral.identifier, name: record.name, family: record.family)
        connectedDeviceContinuation?.yield(device)
    }
}

private extension ButtonPressType {
    /// Wire encoding unverified — see `LegacyDeviceController` header note.
    var wireValue: UInt8 {
        switch self {
        case .singlePress: return 0x01
        case .doublePress: return 0x02
        case .longPress: return 0x03
        }
    }
}

private extension ButtonAction {
    var wireValue: UInt8 {
        switch self {
        case .none: return 0x00
        case .fireStimulus: return 0x01
        case .toggleMute: return 0x02
        case .snoozeActiveAlarm: return 0x03
        }
    }
}

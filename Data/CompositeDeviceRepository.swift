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
    let central = BluetoothCentralManager()
    lazy var legacy = LegacyDeviceController(central: central, protocolStore: protocolStore)
    lazy var scMax = SCMaxDeviceController(central: central)
    lazy var deviceInfoReader = DeviceInformationReader(central: central)
    let store: PairedDeviceStore
    let settingsStore: StimulusSettingsStore
    let protocolStore: LegacyProtocolStore

    var connectionStateContinuation: AsyncStream<DeviceConnectionState>.Continuation?
    var connectedDeviceContinuation: AsyncStream<PavlokDevice?>.Continuation?

    var connectedPeripheral: CBPeripheral?
    var connectedFamily: DeviceFamily?
    var didStart = false
    var isAutoReconnecting = false

    private(set) var stimulusSettings: StimulusSettings

    // Only touched on the main actor; `nonisolated(unsafe)` so `deinit`
    // (always nonisolated) can cancel them.
    nonisolated(unsafe) private var stateTask: Task<Void, Never>?
    nonisolated(unsafe) private var disconnectionTask: Task<Void, Never>?
    nonisolated(unsafe) private var restoreTask: Task<Void, Never>?
    nonisolated(unsafe) var reconnectTask: Task<Void, Never>?

    init(
        store: PairedDeviceStore = PairedDeviceStore(),
        settingsStore: StimulusSettingsStore = StimulusSettingsStore(),
        protocolStore: LegacyProtocolStore = LegacyProtocolStore()
    ) {
        self.store = store
        self.settingsStore = settingsStore
        self.protocolStore = protocolStore
        self.stimulusSettings = settingsStore.load()
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

    // MARK: - Scanning

    /// Yields matching devices as they turn up.
    ///
    /// Two things beyond a plain `scanForPeripherals` matter here, and both
    /// were reasons a device that is *already paired to the phone* appeared
    /// to be undiscoverable:
    ///
    /// 1. The scan waits for `.poweredOn`. Right after launch
    ///    `CBCentralManager` is `.unknown` for a moment, and a scan started
    ///    in that window returns nothing and never recovers.
    /// 2. Peripherals iOS is already connected to, and previously-bonded
    ///    ones, are seeded in. A connected device has stopped advertising,
    ///    so it can never appear in `didDiscover` — scanning alone will
    ///    never find the device you already paired.
    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice> {
        connectionStateContinuation?.yield(.scanning)
        let seeds = [store.load()?.peripheralIdentifier].compactMap { $0 }
        let discoveries = central.startScan(serviceUUIDs: nil, seedIdentifiers: seeds)
        return AsyncStream { continuation in
            let task = Task {
                var seen: Set<UUID> = []
                for await discovery in discoveries {
                    guard let name = discovery.displayName else { continue }
                    guard let family = DeviceFamily.matching(name: name, in: families) else {
                        BLELog.debug("Ignoring \(name) — no matching device family")
                        continue
                    }
                    guard seen.insert(discovery.peripheral.identifier).inserted else { continue }
                    let alreadyConnected = discovery.wasAlreadyConnected ? " (already connected to phone)" : ""
                    BLELog.info("Matched \(name) as \(family.displayName)\(alreadyConnected)")
                    continuation.yield(PavlokDevice(
                        peripheralIdentifier: discovery.peripheral.identifier,
                        name: name,
                        family: family
                    ))
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

    // MARK: - Connection

    func connect(to device: PavlokDevice) async throws {
        reconnectTask?.cancel()
        connectionStateContinuation?.yield(.connecting)
        central.stopScan()

        // `retrievePeripherals(withIdentifiers:)` is the direct route and
        // works for anything the phone has seen before — which includes
        // everything we just handed to the UI from a scan. Re-scanning to
        // find the same peripheral again (what this used to do) fails
        // outright for a device that is already connected at the system
        // level, because it never advertises.
        guard let peripheral = central.retrieveKnownPeripheral(device.peripheralIdentifier) else {
            BLELog.error("No peripheral for identifier \(device.peripheralIdentifier)")
            connectionStateContinuation?.yield(.failed("Device not found"))
            throw BluetoothCentralManager.BluetoothError.connectFailed(nil)
        }

        do {
            try await central.connect(peripheral)
            adopt(peripheral, family: device.family, name: device.name)
        } catch {
            BLELog.error("Connect failed: \(error.localizedDescription)")
            connectionStateContinuation?.yield(.failed(error.localizedDescription))
            throw error
        }
    }

    func adopt(_ peripheral: CBPeripheral, family: DeviceFamily, name: String) {
        connectedPeripheral = peripheral
        connectedFamily = family
        store.save(peripheralIdentifier: peripheral.identifier, name: name, family: family)
        connectionStateContinuation?.yield(.connected)

        var device = PavlokDevice(
            peripheralIdentifier: peripheral.identifier,
            name: name,
            family: family,
            lastConnectedAt: .now
        )
        connectedDeviceContinuation?.yield(device)

        Task { [weak self] in
            guard let self else { return }
            // Dump the GATT table once per connection. It costs one discovery
            // round-trip and it is the difference between "the zap did
            // nothing" and "the zap went to a characteristic this device
            // doesn't have".
            _ = try? await dumpGATT(readingValues: false)

            // Then fill in model/firmware/battery and re-publish. Without
            // this the connected device's `info` stays at its empty default
            // for the whole session, so the battery indicator on the remote
            // never appears no matter what the hardware reports.
            guard let info = try? await deviceInfoReader.read(from: peripheral),
                  connectedPeripheral?.identifier == peripheral.identifier else { return }
            device.info = info
            let battery = info.batteryLevelPercent.map(String.init) ?? "?"
            BLELog.info("Device info: model=\(info.modelNumber ?? "?") fw=\(info.firmwareRevision ?? "?") battery=\(battery)")
            connectedDeviceContinuation?.yield(device)
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

    // MARK: - Stimulus

    func fire(_ stimulus: StimulusConfig) async throws {
        let (peripheral, family) = try requireConnection()
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.fire(stimulus, on: peripheral)
        case .shockClockMax:
            try await scMax.fire(stimulus, on: peripheral)
        }
    }

    @discardableResult
    func saveStimulusConfig(_ config: StimulusConfig) async -> StimulusSyncState {
        stimulusSettings[config.kind] = config
        settingsStore.save(stimulusSettings)

        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            return .localOnly(reason: "No device connected")
        }
        do {
            switch family {
            case .pavlok2, .pavlok3:
                try await legacy.saveStimulusConfig(config, on: peripheral)
            case .shockClockMax:
                try await scMax.saveStimulusConfig(config, on: peripheral)
            }
            return .syncedToDevice
        } catch {
            BLELog.error("Saving \(config.kind.rawValue) config to device failed: \(error.localizedDescription)")
            return .localOnly(reason: error.localizedDescription)
        }
    }

    // MARK: - Everything else

    func readDeviceInfo() async throws -> DeviceInfo {
        let (peripheral, _) = try requireConnection()
        return try await deviceInfoReader.read(from: peripheral)
    }

    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws {
        let (peripheral, family) = try requireConnection()
        switch family {
        case .pavlok2, .pavlok3:
            // `BleManager::setButtonAction` writes to the *setup* service,
            // not the application one. The payload it builds is variable
            // length and depends on the action, so the two bytes below are
            // still a guess — but they are at least aimed at the right
            // characteristic now.
            let payload = Data([press.wireValue, config.action.wireValue])
            try await central.write(
                payload,
                to: LegacyGATT.setupCharacteristic,
                serviceUUID: LegacyGATT.setupService,
                on: peripheral
            )
        case .shockClockMax:
            throw SCMaxDeviceController.ControllerError.notImplemented(
                "Button config opcode not recovered — see BLE/SCMax/ProtocolMap.swift"
            )
        }
    }

    func syncDeviceAlarm(_ alarm: Alarm) async throws {
        let (peripheral, family) = try requireConnection()
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.syncAlarm(alarm, on: peripheral)
        case .shockClockMax:
            try await scMax.syncAlarm(alarm, on: peripheral)
        }
    }

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {
        let (peripheral, family) = try requireConnection()
        switch family {
        case .pavlok2, .pavlok3:
            try await legacy.deleteAlarm(id, on: peripheral)
        case .shockClockMax:
            try await scMax.deleteAlarm(id, on: peripheral)
        }
    }

    func requireConnection() throws -> (CBPeripheral, DeviceFamily) {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            BLELog.error("Operation requires a connected device, but none is connected")
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        return (peripheral, family)
    }
}

// MARK: - Protocol diagnostics
//
// Split into an extension purely to keep the main type's body readable; these
// exist for the Diagnostics screen and no normal flow touches them.
extension CompositeDeviceRepository {
    func dumpGATT(readingValues: Bool) async throws -> [GATTCharacteristicDump] {
        let (peripheral, _) = try requireConnection()
        return try await central.dumpGATT(on: peripheral, readingValues: readingValues)
    }

    func writeRaw(_ data: Data, characteristicUUID: String, serviceUUID: String) async throws {
        let (peripheral, _) = try requireConnection()
        try await central.write(
            data,
            to: CBUUID(string: characteristicUUID),
            serviceUUID: CBUUID(string: serviceUUID),
            on: peripheral
        )
    }

    @discardableResult
    func startListeningForDeviceEvents() async throws -> Int {
        let (peripheral, _) = try requireConnection()
        return try await central.captureAllNotifications(on: peripheral)
    }

    func stopListeningForDeviceEvents() {
        central.stopNotificationCapture()
    }

    func deviceEventStream() async throws -> AsyncStream<DeviceEvent> {
        let (peripheral, _) = try requireConnection()
        return try await central.streamAllNotifications(on: peripheral)
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

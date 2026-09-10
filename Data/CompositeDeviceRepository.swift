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

    // Multi-consumer: the device UI *and* the poke trigger both observe these.
    // A single AsyncStream would let one consumer starve the other.
    let connectionStateHub = StreamHub<DeviceConnectionState>()
    let connectedDeviceHub = StreamHub<PavlokDevice?>()

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

    var connectionState: AsyncStream<DeviceConnectionState> {
        startIfNeeded()
        return connectionStateHub.stream()
    }

    var connectedDevice: AsyncStream<PavlokDevice?> {
        startIfNeeded()
        return connectedDeviceHub.stream()
    }

    /// Wires up event observation and kicks off an initial reconnect
    /// attempt. Deferred to first access of either stream (rather than
    /// `init`) so nothing tries to reconnect before there's a subscriber; the
    /// `StreamHub`s replay the latest state to anyone who subscribes later.
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
        connectionStateHub.yield(.scanning)
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
        connectionStateHub.yield(.disconnected)
    }

    // MARK: - Connection

    func connect(to device: PavlokDevice) async throws {
        reconnectTask?.cancel()
        connectionStateHub.yield(.connecting)
        central.stopScan()

        // `retrievePeripherals(withIdentifiers:)` is the direct route and
        // works for anything the phone has seen before — which includes
        // everything we just handed to the UI from a scan. Re-scanning to
        // find the same peripheral again (what this used to do) fails
        // outright for a device that is already connected at the system
        // level, because it never advertises.
        guard let peripheral = central.retrieveKnownPeripheral(device.peripheralIdentifier) else {
            BLELog.error("No peripheral for identifier \(device.peripheralIdentifier)")
            connectionStateHub.yield(.failed("Device not found"))
            throw BluetoothCentralManager.BluetoothError.connectFailed(nil)
        }

        do {
            try await central.connect(peripheral)
            adopt(peripheral, family: device.family, name: device.name)
        } catch {
            BLELog.error("Connect failed: \(error.localizedDescription)")
            connectionStateHub.yield(.failed(error.localizedDescription))
            throw error
        }
    }

    func adopt(_ peripheral: CBPeripheral, family: DeviceFamily, name: String) {
        connectedPeripheral = peripheral
        connectedFamily = family
        store.save(peripheralIdentifier: peripheral.identifier, name: name, family: family)
        connectionStateHub.yield(.connected)

        var device = PavlokDevice(
            peripheralIdentifier: peripheral.identifier,
            name: name,
            family: family,
            lastConnectedAt: .now
        )
        connectedDeviceHub.yield(device)

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
            connectedDeviceHub.yield(device)
        }
    }

    func disconnect() async {
        reconnectTask?.cancel()
        if let peripheral = connectedPeripheral {
            central.disconnect(peripheral)
        }
        connectedPeripheral = nil
        connectedFamily = nil
        connectionStateHub.yield(.disconnected)
        connectedDeviceHub.yield(nil)
    }

    func forgetPairedDevice() async {
        reconnectTask?.cancel()
        if let peripheral = connectedPeripheral {
            central.disconnect(peripheral)
        }
        connectedPeripheral = nil
        connectedFamily = nil
        store.clear()
        connectionStateHub.yield(.disconnected)
        connectedDeviceHub.yield(nil)
    }

    // MARK: - Stimulus

    func fire(_ stimulus: StimulusConfig) async throws {
        let (peripheral, family) = try requireConnection()
        try await controller(for: family).fire(stimulus, on: peripheral)
    }

    @discardableResult
    func saveStimulusConfig(_ config: StimulusConfig) async -> StimulusSyncState {
        stimulusSettings[config.kind] = config
        settingsStore.save(stimulusSettings)

        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            return .localOnly(reason: "No device connected")
        }
        do {
            try await controller(for: family).saveStimulusConfig(config, on: peripheral)
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

    func syncDeviceAlarm(_ alarm: Alarm) async throws {
        let (peripheral, family) = try requireConnection()
        try await controller(for: family).syncAlarm(alarm, on: peripheral)
    }

    func deleteDeviceAlarm(_ id: Alarm.ID) async throws {
        let (peripheral, family) = try requireConnection()
        try await controller(for: family).deleteAlarm(id, on: peripheral)
    }

    func requireConnection() throws -> (CBPeripheral, DeviceFamily) {
        guard let peripheral = connectedPeripheral, let family = connectedFamily else {
            BLELog.error("Operation requires a connected device, but none is connected")
            throw BluetoothCentralManager.BluetoothError.bluetoothUnavailable
        }
        return (peripheral, family)
    }

    /// The one place a device family maps to its controller — everywhere
    /// above just calls through this instead of repeating the switch.
    private func controller(for family: DeviceFamily) -> DeviceController {
        switch family {
        case .pavlok2, .pavlok3: return legacy
        case .shockClockMax: return scMax
        }
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

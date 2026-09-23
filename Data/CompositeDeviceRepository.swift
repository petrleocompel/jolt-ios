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
    nonisolated(unsafe) private var foregroundTask: Task<Void, Never>?
    nonisolated(unsafe) var reconnectTask: Task<Void, Never>?
    /// The live subscription (or slow poll) on the battery characteristic.
    /// One per connection — see `startBatteryMonitoring`.
    nonisolated(unsafe) var batteryMonitorTask: Task<Void, Never>?

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
        foregroundTask?.cancel()
        reconnectTask?.cancel()
        batteryMonitorTask?.cancel()
    }

    var connectionState: AsyncStream<DeviceConnectionState> {
        startIfNeeded()
        return connectionStateHub.stream()
    }

    var connectedDevice: AsyncStream<PavlokDevice?> {
        startIfNeeded()
        return connectedDeviceHub.stream()
    }

    /// Deliberately does *not* call `startIfNeeded()` — this is a plain
    /// question about persisted state, and answering it shouldn't be what
    /// powers up Bluetooth.
    var hasPairedDevice: Bool { store.load() != nil }

    var pairedDeviceName: String? { store.load()?.name }

    func reconnect() async {
        startIfNeeded()
        await attemptAutoReconnect()
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
        foregroundTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: Self.willEnterForeground) {
                await self?.refreshDeviceInfoIfConnected()
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
                        family: family,
                        rssi: discovery.rssi
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

        let device = PavlokDevice(
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
            await publishDeviceInfo(for: peripheral)
            guard connectedPeripheral?.identifier == peripheral.identifier else { return }
            startBatteryMonitoring(for: peripheral)
        }
    }

    func disconnect() async {
        reconnectTask?.cancel()
        stopBatteryMonitoring()
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
        stopBatteryMonitoring()
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

    /// How long `fire` waits for a dropped link to come back before giving
    /// up. Sized for the silent push that carries an incoming poke: iOS
    /// gives that wake-up a tight, unpredictable budget, and a stimulus that
    /// lands ten seconds late is worse than one reported undelivered.
    private static let reconnectBudgetForFiring: Duration = .seconds(4)

    func fire(_ stimulus: StimulusConfig) async throws {
        let (peripheral, family) = try await connectionForFiring()
        try await controller(for: family).fire(stimulus, on: peripheral)
    }

    /// A stimulus is the one operation worth waiting on a reconnect for.
    ///
    /// The silent push carrying a poke routinely wakes the app before
    /// CoreBluetooth has restored the link — and in that process
    /// `startIfNeeded()` has usually never run at all, because no view
    /// subscribed to a connection stream, so nothing has yet asked Bluetooth
    /// for anything. Failing instantly there reports a wearable that is
    /// sitting on the user's wrist as `deviceNotConnected`. Kick the same
    /// auto-reconnect the UI would and give it a bounded moment to land.
    ///
    /// An unpaired phone still throws immediately: there is nothing to wait
    /// for, and the device-free paths (sending a quick poke, receiving one
    /// with no wearable) must stay instant.
    private func connectionForFiring() async throws -> (CBPeripheral, DeviceFamily) {
        let waiter = ConnectionWaiter<(CBPeripheral, DeviceFamily)>(
            budget: Self.reconnectBudgetForFiring,
            isPaired: { [weak self] in self?.hasPairedDevice ?? false },
            currentConnection: { [weak self] in
                guard let self, let peripheral = connectedPeripheral, let family = connectedFamily else {
                    return nil
                }
                return (peripheral, family)
            },
            // Deliberately not awaited: `reconnect()` can spend its own
            // power-on timeout before it even starts connecting, and the
            // budget above is meant to cover the whole wait. The attempt
            // outlives that budget either way — a poke that misses this
            // window is retried by the alert half of its push (see
            // `LocalStimulusFirer`), by which time this reconnect has
            // usually landed.
            startReconnect: { [weak self] in Task { await self?.reconnect() } }
        )
        guard let connection = await waiter.connection() else { return try requireConnection() }
        return connection
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

    func writeRaw(_ data: Data, characteristicUUID: String, serviceUUID: String, mode: RawWriteMode) async throws {
        let (peripheral, _) = try requireConnection()
        try await central.write(
            data,
            to: CBUUID(string: characteristicUUID),
            serviceUUID: CBUUID(string: serviceUUID),
            on: peripheral,
            type: mode == .withResponse ? .withResponse : .withoutResponse
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

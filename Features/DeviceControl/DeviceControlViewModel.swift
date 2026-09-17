import Foundation
import Observation

@MainActor
@Observable
final class DeviceControlViewModel {
    private let repository: DeviceRepository
    // `@ObservationIgnored`: bookkeeping, not UI state — also required for
    // `nonisolated(unsafe)` to apply (the @Observable macro rejects it on a
    // tracked stored property). Touched from `init` (main actor) and
    // `deinit` (always nonisolated, even on an @MainActor class) to call
    // `.cancel()`, which is safe from any context.
    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var deviceObservationTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var scanTask: Task<Void, Never>?

    private(set) var connectionState: DeviceConnectionState = .disconnected
    private(set) var connectedDevice: PavlokDevice?
    private(set) var discoveredDevices: [PavlokDevice] = []
    var lastError: String?

    /// Mirrored from the repository so views can observe it — the repository
    /// itself isn't `@Observable`, so reading `repository.hasPairedDevice`
    /// straight from a `body` would never refresh when pairing changes.
    private(set) var hasPairedDevice: Bool
    /// The paired device's name, kept even while it's unreachable. Mirrored
    /// for the same reason as `hasPairedDevice`.
    private(set) var pairedDeviceName: String?

    /// Per-kind stimulus defaults, mirrored from the repository so views can
    /// bind to them directly.
    private(set) var stimulusSettings: StimulusSettings

    /// Short-lived confirmation of the last action, shown inline on the
    /// remote rather than as an alert — firing a stimulus is something you
    /// do repeatedly, and a modal per tap would be unusable.
    private(set) var lastActionMessage: String?
    @ObservationIgnored
    nonisolated(unsafe) private var lastActionResetTask: Task<Void, Never>?

    init(repository: DeviceRepository) {
        self.repository = repository
        self.stimulusSettings = repository.stimulusSettings
        self.hasPairedDevice = repository.hasPairedDevice
        self.pairedDeviceName = repository.pairedDeviceName
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await state in repository.connectionState {
                self.connectionState = state
            }
        }
        deviceObservationTask = Task { [weak self] in
            guard let self else { return }
            for await device in repository.connectedDevice {
                self.connectedDevice = device
                // A successful connect is also what persists the pairing.
                self.hasPairedDevice = repository.hasPairedDevice
                self.pairedDeviceName = repository.pairedDeviceName
            }
        }
    }

    deinit {
        observationTask?.cancel()
        deviceObservationTask?.cancel()
        scanTask?.cancel()
        lastActionResetTask?.cancel()
    }

    func startScan(for families: Set<DeviceFamily> = Set(DeviceFamily.allCases)) {
        discoveredDevices = []
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            for await device in repository.startScan(for: families) where !discoveredDevices.contains(device) {
                discoveredDevices.append(device)
            }
        }
    }

    func stopScan() {
        scanTask?.cancel()
        repository.stopScan()
    }

    func connect(to device: PavlokDevice) {
        stopScan()
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.connect(to: device)
            } catch {
                BLELog.error("Connect to \(device.name) failed: \(error.localizedDescription)")
                lastError = "Couldn't connect to \(device.name). Move closer and try again."
            }
        }
    }

    func disconnect() {
        Task { await repository.disconnect() }
    }

    func forgetPairedDevice() {
        Task { [weak self] in
            guard let self else { return }
            await repository.forgetPairedDevice()
            hasPairedDevice = repository.hasPairedDevice
            pairedDeviceName = repository.pairedDeviceName
        }
    }

    /// "Try again" on a dropped or failed connection.
    func reconnect() {
        lastError = nil
        Task { await repository.reconnect() }
    }

    func fire(_ stimulus: StimulusConfig) {
        // Fire controls stay tappable without a device so the tap can say
        // why nothing happened, rather than sitting there disabled.
        guard connectedDevice != nil else {
            lastError = Self.noDeviceMessage
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await repository.fire(stimulus)
                note("\(stimulus.kind.displayName) sent at \(stimulus.intensity)%")
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Saves `config` as the default for its kind and pushes it to the
    /// wearable when one is connected.
    func saveStimulusConfig(_ config: StimulusConfig) {
        stimulusSettings[config.kind] = config
        Task { [weak self] in
            guard let self else { return }
            let result = await repository.saveStimulusConfig(config)
            stimulusSettings = repository.stimulusSettings
            switch result {
            case .syncedToDevice:
                note("\(config.kind.displayName) saved to device")
            case .localOnly(let reason):
                note("\(config.kind.displayName) saved on phone only\(reason.map { " — \($0)" } ?? "")")
            }
        }
    }

    static let noDeviceMessage = "No device connected. Pair one to fire."

    func dumpGATT(readingValues: Bool = false) async throws -> [GATTCharacteristicDump] {
        try await repository.dumpGATT(readingValues: readingValues)
    }

    func writeRaw(
        _ data: Data,
        characteristicUUID: String,
        serviceUUID: String,
        mode: RawWriteMode = .withResponse
    ) async throws {
        try await repository.writeRaw(data, characteristicUUID: characteristicUUID, serviceUUID: serviceUUID, mode: mode)
    }

    @discardableResult
    func startListeningForDeviceEvents() async throws -> Int {
        try await repository.startListeningForDeviceEvents()
    }

    func stopListeningForDeviceEvents() {
        repository.stopListeningForDeviceEvents()
    }

    private func note(_ message: String) {
        lastActionMessage = message
        lastActionResetTask?.cancel()
        lastActionResetTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.lastActionMessage = nil }
        }
    }

    func readDeviceInfo() async throws -> DeviceInfo {
        try await repository.readDeviceInfo()
    }

    func setButtonConfig(_ config: ButtonConfig) async throws {
        try await repository.setButtonConfig(config)
    }

    func readButtonConfig() async throws -> ButtonConfigReport {
        try await repository.readButtonConfig()
    }

    func readRawButtonConfig() async throws -> Data {
        try await repository.readRawButtonConfig()
    }
}

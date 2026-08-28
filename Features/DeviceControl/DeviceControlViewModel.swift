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

    /// True while a *manually initiated* connect (from onboarding) is in
    /// flight — distinguishes that from an automatic reconnect-on-launch,
    /// which also passes through `connectionState == .connecting` but
    /// should show a different screen (see `RootView`).
    private(set) var isManualConnectInProgress = false

    func connect(to device: PavlokDevice) {
        stopScan()
        isManualConnectInProgress = true
        Task { [weak self] in
            guard let self else { return }
            defer { isManualConnectInProgress = false }
            do {
                try await repository.connect(to: device)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func disconnect() {
        Task { await repository.disconnect() }
    }

    func forgetPairedDevice() {
        Task { await repository.forgetPairedDevice() }
    }

    func fire(_ stimulus: StimulusConfig) {
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

    func dumpGATT(readingValues: Bool = false) async throws -> [GATTCharacteristicDump] {
        try await repository.dumpGATT(readingValues: readingValues)
    }

    func writeRaw(_ data: Data, characteristicUUID: String, serviceUUID: String) async throws {
        try await repository.writeRaw(data, characteristicUUID: characteristicUUID, serviceUUID: serviceUUID)
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

    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws {
        try await repository.setButtonConfig(config, press: press)
    }
}

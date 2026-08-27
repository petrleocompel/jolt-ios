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

    init(repository: DeviceRepository) {
        self.repository = repository
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
                lastError = "\(error)"
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
            } catch {
                lastError = "\(error)"
            }
        }
    }

    func readDeviceInfo() async throws -> DeviceInfo {
        try await repository.readDeviceInfo()
    }

    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws {
        try await repository.setButtonConfig(config, press: press)
    }
}

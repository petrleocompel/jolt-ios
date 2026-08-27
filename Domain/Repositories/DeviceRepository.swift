import Foundation

/// The one door between UI and hardware. `BLE/` implements this against
/// CoreBluetooth; `Features/` never imports CoreBluetooth directly, so a
/// future Peelco backend or a simulator implementation can swap in without
/// touching UI code.
///
/// `@MainActor`: CoreBluetooth callbacks and SwiftUI view models are both
/// main-actor-bound in this codebase, so every conformer is too — pinning it
/// here avoids `nonisolated` conformance mismatches at each call site.
@MainActor
protocol DeviceRepository {
    var connectionState: AsyncStream<DeviceConnectionState> { get }
    var connectedDevice: AsyncStream<PavlokDevice?> { get }

    func startScan(for families: Set<DeviceFamily>) -> AsyncStream<PavlokDevice>
    func stopScan()
    func connect(to device: PavlokDevice) async throws
    func disconnect() async
    /// Disconnects (if connected) and forgets the persisted pairing, so the
    /// next launch goes back to onboarding instead of auto-reconnecting.
    func forgetPairedDevice() async
    func fire(_ stimulus: StimulusConfig) async throws
    func readDeviceInfo() async throws -> DeviceInfo
    func setButtonConfig(_ config: ButtonConfig, press: ButtonPressType) async throws
    /// Pushes an `AlarmLocation.device` alarm onto the wearable's own RTC so
    /// it fires even if the phone is off. See `LegacyDeviceController` /
    /// `SCMaxDeviceController` for what's actually implemented per family.
    func syncDeviceAlarm(_ alarm: Alarm) async throws
    func deleteDeviceAlarm(_ id: Alarm.ID) async throws
}

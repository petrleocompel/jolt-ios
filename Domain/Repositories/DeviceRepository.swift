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

    // MARK: Per-kind stimulus defaults

    /// The saved defaults for zap / vibe / beep. Always available, device or
    /// no device — they're stored on the phone.
    var stimulusSettings: StimulusSettings { get }
    /// Persists `config` for its kind and, when a device is connected, also
    /// writes it to the wearable so its own button and alarms use the same
    /// value. The return value says which of those two actually happened.
    @discardableResult
    func saveStimulusConfig(_ config: StimulusConfig) async -> StimulusSyncState

    // MARK: Protocol diagnostics

    /// Every service and characteristic the connected device exposes.
    /// Diagnostics renders this; it's also the fastest way to tell a wrong
    /// UUID from a wrong payload while the wire format is still partly
    /// inferred.
    ///
    /// - Parameter readingValues: additionally reads each readable
    ///   characteristic. Reads cannot fire a stimulus, so this is the safe
    ///   half of identifying the config characteristics.
    func dumpGATT(readingValues: Bool) async throws -> [GATTCharacteristicDump]
    /// Writes raw bytes to an arbitrary characteristic. Powers the Protocol
    /// lab. Not used by any normal app flow.
    func writeRaw(_ data: Data, characteristicUUID: String, serviceUUID: String) async throws
    /// Subscribes to every notifying characteristic and logs what arrives, so
    /// an action performed on the device itself (pressing its button) can be
    /// observed in the device's own encoding. Returns how many were
    /// subscribed.
    @discardableResult
    func startListeningForDeviceEvents() async throws -> Int
    func stopListeningForDeviceEvents()
}

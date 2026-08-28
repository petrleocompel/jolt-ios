import CoreBluetooth
import Foundation

/// Talks to Pavlok 2/3 over `LegacyGATT`.
///
/// Each stimulus kind has its own characteristic (see `LegacyGATT` for the
/// evidence), so a fire is a single write of the stimulus parameters — there
/// is no opcode byte. The parameter order follows `ZapConfig(count:, level:)`
/// / `MotorConfig(count:, level:)` / `PiezoConfig(count:, level:)`, whose
/// field names and order are recovered from the freezed `toString`
/// fragments in the Dart snapshot. The *byte* order between those two
/// fields is still an inference; `Diagnostics → Protocol lab` can send
/// arbitrary bytes to any characteristic to settle it against real hardware.
struct LegacyDeviceController {
    private let central: BluetoothCentralManager
    private let protocolStore: LegacyProtocolStore

    init(central: BluetoothCentralManager, protocolStore: LegacyProtocolStore = LegacyProtocolStore()) {
        self.central = central
        self.protocolStore = protocolStore
    }

    /// `count` first, then `level`.
    ///
    /// That order is the one weak signal available: the freezed `toString`
    /// fragments in the Dart snapshot read `ZapConfig(count: `, `, level: `,
    /// so `count` is the first declared field of each config. Declaration
    /// order is not proof of wire order — if a single zap arrives as a burst
    /// of twenty, the two are swapped. `Diagnostics → Protocol lab` sends
    /// arbitrary bytes to settle it against real hardware.
    ///
    /// Intensity goes out as a 0...100 percentage rather than a scaled
    /// 0...255 byte: the app's own control is a percentage and the field is
    /// named `zapIntensity`.
    static func payload(for stimulus: StimulusConfig) -> Data {
        Data([
            UInt8(clamping: stimulus.repetitions),
            UInt8(clamping: stimulus.intensity)
        ])
    }

    func fire(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        let characteristic = protocolStore.characteristic(for: stimulus.kind)
        BLELog.info(
            "Fire \(stimulus.kind.rawValue) intensity=\(stimulus.intensity) reps=\(stimulus.repetitions) → \(characteristic.uuidString)"
        )
        try await central.write(
            Self.payload(for: stimulus),
            to: characteristic,
            serviceUUID: LegacyGATT.service,
            on: peripheral
        )
    }

    /// Writes `stimulus` as the device-side default for its kind, so the
    /// physical button and on-device alarms use it. Same characteristic as
    /// firing; the difference is only that the app also persists it locally.
    ///
    /// If a device turns out to need a distinct "configure" write this is the
    /// one place to change — call sites in `CompositeDeviceRepository` don't
    /// need to know.
    func saveStimulusConfig(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        let characteristic = protocolStore.characteristic(for: stimulus.kind)
        BLELog.info("Save \(stimulus.kind.rawValue) config to device → \(characteristic.uuidString)")
        try await central.write(
            Self.payload(for: stimulus),
            to: characteristic,
            serviceUUID: LegacyGATT.service,
            on: peripheral
        )
    }

    /// Alarm slot layout (hour, minute, day bitmask, enabled, id prefix) is
    /// unverified against real hardware — the alarm characteristics live in
    /// `kApplicationServiceUuid`, whose UUID is inferred the same way as the
    /// stimulus ones.
    func syncAlarm(_ alarm: Alarm, on peripheral: CBPeripheral) async throws {
        var dayBitmask: UInt8 = 0
        for day in alarm.repeatDays {
            dayBitmask |= 1 << UInt8(day.rawValue - 1)
        }
        let payload = Data([
            UInt8(alarm.hour),
            UInt8(alarm.minute),
            dayBitmask,
            alarm.isEnabled ? 1 : 0
        ]) + Data(alarm.id.uuidBytes.prefix(4))
        try await central.write(
            payload,
            to: LegacyGATT.applicationControl,
            serviceUUID: LegacyGATT.applicationService,
            on: peripheral
        )
    }

    func deleteAlarm(_ id: Alarm.ID, on peripheral: CBPeripheral) async throws {
        let payload = Data([0xFF]) + Data(id.uuidBytes.prefix(4))
        try await central.write(
            payload,
            to: LegacyGATT.applicationControl,
            serviceUUID: LegacyGATT.applicationService,
            on: peripheral
        )
    }
}

private extension UUID {
    var uuidBytes: [UInt8] {
        withUnsafeBytes(of: uuid) { Array($0) }
    }
}

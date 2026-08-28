import CoreBluetooth
import Foundation

/// Talks to Pavlok 2/3 over `LegacyGATT`.
///
/// Each stimulus kind has its own characteristic in the config service (see
/// `LegacyGATT`), so there is no opcode byte — the payload is the stimulus
/// parameters and nothing else.
///
/// What the payload *is* remains partly open, and the code reflects that
/// rather than papering over it. Observed on a Pavlok 3 (fw 6.10.0):
///
/// | Characteristic | 2-byte write | Result |
/// |---|---|---|
/// | `1001` | `01 14` | rejected, invalid attribute value length |
/// | `1002` | `01 3C` | rejected, invalid attribute value length |
/// | `1003` | `01 0A` | acknowledged, nothing audible |
///
/// So `1001`/`1002` are fixed-length and not two bytes, and `1003` accepts
/// two but firing is evidently not what it does. The Android binary
/// separates `performDeviceZap` (fire) from `updateDeviceZap` (configure)
/// and contains `encodeTimerStimulusIntensityAndCount`, so intensity and
/// count are packed rather than sent as separate bytes somewhere in this
/// protocol.
///
/// Rather than keep guessing, every write reads the characteristic first and
/// sizes the payload to match — see `payload(for:existing:)`. Diagnostics →
/// "Read all values" shows the whole table non-destructively, and Protocol
/// lab sends arbitrary bytes.
struct LegacyDeviceController {
    private let central: BluetoothCentralManager
    private let protocolStore: LegacyProtocolStore

    init(central: BluetoothCentralManager, protocolStore: LegacyProtocolStore = LegacyProtocolStore()) {
        self.central = central
        self.protocolStore = protocolStore
    }

    /// Builds a payload sized to what the characteristic actually holds.
    ///
    /// The layout is not recovered from the binary — the encoders are AOT
    /// machine code — so this is driven by the device instead. Every config
    /// characteristic is readable, and a BLE characteristic with a fixed
    /// length rejects a wrong-sized write with "invalid attribute value
    /// length", which is exactly what a blind 2-byte write to `1001` and
    /// `1002` produced. Reading first turns that guess into a measurement.
    ///
    /// - `existing` nil: no read was possible, fall back to two bytes.
    /// - 1 byte: intensity and count are packed into one value. The binary
    ///   has a function named `encodeTimerStimulusIntensityAndCount`, so a
    ///   combined encoding is how this firmware thinks about it; intensity
    ///   alone is the closest safe approximation until the packing is known.
    /// - 2 bytes: `count` then `level`, the field order of
    ///   `ZapConfig(count:, level:)` in the Dart snapshot.
    /// - longer: preserve whatever the device already has and overwrite only
    ///   the first two bytes, so an unknown trailing field isn't clobbered.
    static func payload(for stimulus: StimulusConfig, existing: Data?) -> Data {
        let level = UInt8(clamping: stimulus.intensity)
        let count = UInt8(clamping: stimulus.repetitions)

        guard let existing, !existing.isEmpty else { return Data([count, level]) }
        switch existing.count {
        case 1:
            return Data([level])
        case 2:
            return Data([count, level])
        default:
            var bytes = existing
            bytes[bytes.startIndex] = count
            bytes[bytes.index(after: bytes.startIndex)] = level
            return bytes
        }
    }

    /// Reads the characteristic before writing it, both to size the payload
    /// and to record what was there. The previous value is the single most
    /// useful clue for identifying which output a characteristic drives, and
    /// a read cannot fire a stimulus.
    private func write(_ stimulus: StimulusConfig, on peripheral: CBPeripheral, action: String) async throws {
        let characteristic = protocolStore.characteristic(for: stimulus.kind)
        let existing = try? await central.read(
            characteristic,
            from: LegacyGATT.service,
            on: peripheral,
            timeout: .seconds(3)
        )
        if let existing {
            let hex = existing.map { String(format: "%02X", $0) }.joined(separator: " ")
            BLELog.info("\(characteristic.uuidString) currently holds \(existing.count) byte(s): \(hex)")
        } else {
            BLELog.error("Could not read \(characteristic.uuidString) — writing a two-byte payload blind")
        }

        let payload = Self.payload(for: stimulus, existing: existing)
        BLELog.info(
            "\(action) \(stimulus.kind.rawValue) intensity=\(stimulus.intensity) reps=\(stimulus.repetitions) → \(characteristic.uuidString)"
        )
        try await central.write(payload, to: characteristic, serviceUUID: LegacyGATT.service, on: peripheral)
    }

    func fire(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        try await write(stimulus, on: peripheral, action: "Fire")
    }

    /// Writes `stimulus` as the device-side default for its kind, so the
    /// physical button and on-device alarms use it.
    ///
    /// The Android app separates these two: `performDeviceZap` fires,
    /// `updateDeviceZap` configures. They may well be different
    /// characteristics — a write to `1003` is acknowledged but nothing
    /// audible happens, which is what configuring rather than firing looks
    /// like. Until that is settled both go to the same place; this is the one
    /// spot to change when it is.
    func saveStimulusConfig(_ stimulus: StimulusConfig, on peripheral: CBPeripheral) async throws {
        try await write(stimulus, on: peripheral, action: "Save")
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

import CoreBluetooth

/// Pavlok 2 / Pavlok 3 proprietary GATT layout.
///
/// ## What is confirmed
/// The Android binary's `pavlok_flutter_ble/src/ble_manager/ble_uuids_constants.dart`
/// declares these constants (names recovered verbatim from the Dart snapshot's
/// string table — see `docs/RE-FINDINGS.md` §3):
///
///     kConfigServiceUuid          kZapCaracUuid
///     kApplicationServiceUuid     kVibrationCaracUuid
///     kSetupServiceUuid           kBeepCaracUuid
///     kDiagnosticServiceUuid      kHandDetectCaracUuid
///     kFirmwareServiceUuid        kTimeCaracUuid
///     kNotificationServiceUuid    kApplicationControlCharcUuid
///     kBatteryServiceUuid         kApplicationAlarmNotifyCharcUuid
///     kDeviceInformationServiceUuid
///                                 kApplicationAlarmLoadedCharacUuid
///                                 kApplicationDownloadCharcUuid
///                                 kSetupCharacUuid
///                                 kDaqControlCharacUuid
///                                 kDiagnosticCommandCharcUuid
///                                 kFirmwareCharacUuid
///                                 kBatteryDiagnosticCaracUuid
///                                 kBatteryCracUuid / cccdUuid
///
/// The decisive fact for this file: **zap, vibration and beep are three
/// separate characteristics, not one control point with an opcode byte.**
/// The previous version of this file modelled them as a single write
/// characteristic at `0x1001` with a leading opcode — that is wrong twice
/// over, because `0x1001` is a *service*, and because no opcode is involved.
///
/// The 16 proprietary UUIDs present in the binary are, in full:
/// `0x0001 0x0008 0x1001 0x1002 0x1003 0x1005 0x1006 0x1008 0x2002 0x2009
/// 0x200A 0x5001 0x5002 0x5003 0x6002 0x7001`.
///
/// ## What is still inferred
/// Which of the five `0x10xx` characteristics is zap vs. vibration vs. beep.
/// The string table proves the constants exist but not their values (those
/// are AOT machine code). The assignment below follows the declaration order
/// of the constants against the ascending UUIDs in the same block, which is
/// the ordering the rest of the table follows — but it is an inference.
///
/// Rather than ship that inference as fact a second time, it is
/// *overridable*: `LegacyProtocolStore` persists a user-chosen mapping, and
/// Diagnostics → Protocol lab lists what the connected device actually
/// exposes so the mapping can be corrected against real hardware in a few
/// seconds. Verify with Beep first — a mis-assigned Zap is unpleasant.
enum LegacyGATT {
    /// Built from the 16-bit short form, which is how a peripheral reports
    /// Bluetooth-base UUIDs — so `uuidString` here lines up with what a GATT
    /// dump shows and what the Protocol lab picker offers. Comparisons go
    /// through `CBUUID.matches(_:)` regardless, so a device that reports the
    /// long form still resolves (see `CBUUID+Canonical.swift`).
    private static func uuid(_ shortForm: String) -> CBUUID {
        CBUUID(string: shortForm)
    }

    /// `kConfigServiceUuid` — holds the three stimulus characteristics plus
    /// hand-detect and time.
    static let service = uuid("1001")

    /// `kZapCaracUuid` (inferred value).
    static let zap = uuid("1002")
    /// `kVibrationCaracUuid` (inferred value).
    static let vibration = uuid("1003")
    /// `kBeepCaracUuid` (inferred value). `0x1004` is absent from the binary,
    /// so the block is not contiguous.
    static let beep = uuid("1005")
    /// `kTimeCaracUuid` (inferred value).
    static let time = uuid("1006")
    /// `kHandDetectCaracUuid` (inferred value).
    static let handDetect = uuid("1008")

    /// Default characteristic per stimulus kind, before any user override.
    static func defaultCharacteristic(for kind: StimulusKind) -> CBUUID {
        switch kind {
        case .zap: return zap
        case .vibe: return vibration
        case .beep: return beep
        }
    }

    /// Every characteristic in the config service, for the Protocol lab
    /// picker and for "here is what we expected" log lines.
    static let configServiceCharacteristics: [CBUUID] = [zap, vibration, beep, time, handDetect]

    /// `kApplicationServiceUuid` and its characteristics (inferred values —
    /// alarms live here, not in the config service).
    static let applicationService = uuid("2002")
    static let applicationControl = uuid("2009")
    static let applicationAlarmNotify = uuid("200A")

    /// `kSetupServiceUuid` / `kSetupCharacUuid` (inferred values).
    static let setupService = uuid("0001")
    static let setupCharacteristic = uuid("0008")

    /// `kDiagnosticServiceUuid` and friends (inferred values).
    static let diagnosticService = uuid("5001")
    static let diagnosticCommand = uuid("5002")
    static let batteryDiagnostic = uuid("5003")
}

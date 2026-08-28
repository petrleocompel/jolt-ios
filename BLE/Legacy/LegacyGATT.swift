import CoreBluetooth

/// Pavlok 2 / Pavlok 3 proprietary GATT layout.
///
/// ## Confirmed against a real Pavlok 3 (fw 6.10.0, model `Pavlok-S`)
///
/// Services use a vendor base, `156E<n>000-A300-4FEA-897B-86F698D74461`;
/// characteristics inside them are plain 16-bit values. Both halves are
/// corroborated by the Android binary: `re/libapp.strings.txt` contains all
/// six vendor service UUIDs (written with a stray dash, `156E-1000-A300-…`,
/// which is why an earlier pass missed them) and the sixteen 16-bit
/// characteristic UUIDs the app uses.
///
///     156E0000  0001 0002 0003 0004 0005 0006 0007 0008   setup
///     156E1000  1001 1002 1003 1004 1005 1006 1007 1008   config
///     156E2000  2001 … 200A                               application
///     156E4000  4001 4002                                 present, unused by the app
///     156E5000  5001 5002 5003                            diagnostic
///     156E6000  6002                                      notification
///     156E7000  7001 7999                                 firmware / DFU
///
/// An earlier version of this file used `0x1001` as the *service*. That was
/// wrong: `0x1001` is a characteristic, and the service is `156E1000-…`.
/// Every write failed at service lookup, which is why no stimulus ever
/// reached the device.
///
/// ## Still inferred
/// Which characteristic in the config service is zap vs. vibration vs. beep.
/// The binary names them (`kZapCaracUuid`, `kVibrationCaracUuid`,
/// `kBeepCaracUuid`, `kHandDetectCaracUuid`, `kTimeCaracUuid`) but the values
/// those constants hold are AOT machine code. The app references six of the
/// eight config characteristics — `1001 1002 1003 1005 1006 1008`, not
/// `1004`/`1007` — so the three stimulus outputs are among those six.
///
/// The assignment below is the ascending-order reading. Verify it rather
/// than trusting it: Diagnostics → "Read all values" dumps every readable
/// characteristic non-destructively, and Protocol lab sends arbitrary bytes.
/// Test with Beep first — a mis-assigned Zap is a shock.
enum LegacyGATT {
    /// Vendor service base. `n` is the leading nibble: `1` → `156E1000-…`.
    private static func service(_ prefix: String) -> CBUUID {
        CBUUID(string: "156E\(prefix)000-A300-4FEA-897B-86F698D74461")
    }

    /// `kSetupServiceUuid`.
    static let setupService = service("0")
    /// `kConfigServiceUuid` — holds the stimulus characteristics.
    static let service = service("1")
    /// `kApplicationServiceUuid` — alarms and app control.
    static let applicationService = service("2")
    /// Present on the device but never referenced by the Android app.
    static let unusedSensorService = service("4")
    /// `kDiagnosticServiceUuid`.
    static let diagnosticService = service("5")
    /// `kNotificationServiceUuid`.
    static let notificationService = service("6")
    /// `kFirmwareServiceUuid` — `7999` is the usual DFU entry point.
    static let firmwareService = service("7")

    // MARK: Config service characteristics (156E1000)

    /// `kZapCaracUuid` (inferred value).
    static let zap = CBUUID(string: "1001")
    /// `kVibrationCaracUuid` (inferred value).
    static let vibration = CBUUID(string: "1002")
    /// `kBeepCaracUuid` (inferred value).
    static let beep = CBUUID(string: "1003")

    /// The six config characteristics the Android app actually references.
    /// `1004` and `1007` exist on the device but appear nowhere in the
    /// binary, so the stimulus outputs are not among them.
    static let configServiceCharacteristics: [CBUUID] = [
        CBUUID(string: "1001"), CBUUID(string: "1002"), CBUUID(string: "1003"),
        CBUUID(string: "1005"), CBUUID(string: "1006"), CBUUID(string: "1008")
    ]

    static func defaultCharacteristic(for kind: StimulusKind) -> CBUUID {
        switch kind {
        case .zap: return zap
        case .vibe: return vibration
        case .beep: return beep
        }
    }

    // MARK: Application service characteristics (156E2000)

    /// `kApplicationControlCharcUuid` (inferred value; `write|notify`).
    static let applicationControl = CBUUID(string: "2002")
    /// `kApplicationAlarmNotifyCharcUuid` (inferred value; `write|notify`).
    static let applicationAlarmNotify = CBUUID(string: "2009")
    /// `kApplicationAlarmLoadedCharacUuid` (inferred value; `read|notify`).
    static let applicationAlarmLoaded = CBUUID(string: "200A")

    // MARK: Other services

    /// `kSetupCharacUuid` (inferred value).
    static let setupCharacteristic = CBUUID(string: "0008")
    /// `kDiagnosticCommandCharcUuid` (inferred value).
    static let diagnosticCommand = CBUUID(string: "5001")
    /// `kBatteryDiagnosticCaracUuid` (inferred value).
    static let batteryDiagnostic = CBUUID(string: "5002")
}

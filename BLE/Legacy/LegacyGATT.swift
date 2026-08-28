import CoreBluetooth

/// Pavlok 2 / Pavlok 3 GATT layout.
///
/// **Every value here is ground truth**, recovered by decompiling the Android
/// app's Dart AOT snapshot with blutter (OWASP MASTG-TOOL-0116) and reading
/// `pavlok_flutter_ble/src/ble_manager/ble_uuids_constants.dart`. It is no
/// longer inferred from string tables, and it matches a live Pavlok 3
/// (fw 6.10.0) exactly.
///
/// Services use a vendor base written in the Dart source with a stray dash,
/// `156E-1000-A300-4FEA-897B-86F698D74461`; characteristics are 16-bit.
///
/// Note that the service names are not the ones the numbering suggests —
/// `156E5000` is the *application* service and `156E0000` is the diagnostic
/// one, not the other way round.
enum LegacyGATT {
    private static func vendorService(_ prefix: String) -> CBUUID {
        CBUUID(string: "156E\(prefix)000-A300-4FEA-897B-86F698D74461")
    }

    /// `kPavlokService` — holds the diagnostic characteristics.
    static let pavlokService = vendorService("0")
    /// `kConfigServiceUuid` — the stimulus outputs live here.
    static let service = vendorService("1")
    /// `kNotificationServiceUuid`.
    static let notificationService = vendorService("2")
    /// `kApplicationServiceUuid` — alarms and app control.
    static let applicationService = vendorService("5")
    /// `kFirmwareServiceUuid`.
    static let firmwareService = vendorService("6")
    /// `kSetupServiceUuid`.
    static let setupService = vendorService("7")

    // MARK: Config service (156E1000)

    /// `kVibrationCaracUuid`.
    static let vibration = CBUUID(string: "1001")
    /// `kBeepCaracUuid`.
    static let beep = CBUUID(string: "1002")
    /// `kZapCaracUuid`. Note the ordering: zap is *last*, not first — an
    /// earlier guess here had zap and beep swapped, which meant a tap on
    /// "Beep" addressed the zap output.
    static let zap = CBUUID(string: "1003")
    /// `kTimeCaracUuid`.
    static let time = CBUUID(string: "1005")
    /// `kHandDetectCaracUuid`.
    static let handDetect = CBUUID(string: "1006")
    /// `kDaqControlCharacUuid`.
    static let daqControl = CBUUID(string: "1008")

    static func characteristic(for kind: StimulusKind) -> CBUUID {
        switch kind {
        case .zap: return zap
        case .vibe: return vibration
        case .beep: return beep
        }
    }

    /// Kept for the Protocol lab's "expected" list.
    static let configServiceCharacteristics: [CBUUID] = [vibration, beep, zap, time, handDetect, daqControl]

    // MARK: Diagnostic service (156E0000)

    /// `kBatteryDiagnosticCaracUuid`.
    static let batteryDiagnostic = CBUUID(string: "0001")
    /// `kDiagnosticCommandCharcUuid`.
    static let diagnosticCommand = CBUUID(string: "0008")

    // MARK: Notification service (156E2000)

    /// `kEventsNotificationsCharc` — the device's own event stream.
    static let eventsNotifications = CBUUID(string: "2002")
    /// `kNotificationFilesCharc`.
    static let notificationFiles = CBUUID(string: "2009")
    /// `kApplicationAlarmLoadedCharacUuid`.
    static let applicationAlarmLoaded = CBUUID(string: "200A")

    // MARK: Application service (156E5000)

    /// `kApplicationControlCharcUuid`.
    static let applicationControl = CBUUID(string: "5001")
    /// `kApplicationDownloadCharcUuid`.
    static let applicationDownload = CBUUID(string: "5002")
    /// `kApplicationAlarmNotifyCharcUuid`.
    static let applicationAlarmNotify = CBUUID(string: "5003")

    // MARK: Firmware (156E6000) / Setup (156E7000)

    /// `kFirmwareCharacUuid`.
    static let firmwareCharacteristic = CBUUID(string: "6002")
    /// `kSetupCharacUuid`.
    static let setupCharacteristic = CBUUID(string: "7001")
}

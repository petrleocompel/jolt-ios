import CoreBluetooth

/// Pavlok 2 / Pavlok 3 proprietary GATT layout.
///
/// The short-form hex values `1001`, `1002`, `1003`, `1005`, `1006`, `1008`
/// are confirmed — they're printed as strings inside the Android binary's
/// Dart snapshot (see docs/RE-FINDINGS.md §3). Everything else here is a
/// guess built on top of that: the containing service UUID (`1000`, never
/// itself seen in the binary — inferred from the shared `10xx` prefix) and
/// which characteristic does what (role assignment matched to source-file
/// names found nearby, not to any observed traffic). Treat every `static
/// let` below as "worth trying first," not "known correct," until checked
/// against a real device — same caveat as the write payloads in
/// `LegacyDeviceController`.
enum LegacyGATT {
    private static func uuid(_ shortForm: String) -> CBUUID {
        CBUUID(string: "0000\(shortForm)-0000-1000-8000-00805F9B34FB")
    }

    /// Not observed directly — inferred container for the confirmed `10xx` characteristics below.
    static let service = uuid("1000")

    /// Write stimulus command (zap/vibe/beep + intensity + duration).
    static let stimulusControlPoint = uuid("1001")
    /// Notify: stimulus acknowledgement / device event stream.
    static let stimulusNotify = uuid("1002")
    /// Write: button configuration.
    static let buttonConfig = uuid("1003")
    /// Write/notify: device alarm slots.
    static let alarmControlPoint = uuid("1005")
    static let alarmNotify = uuid("1006")
    /// Read/notify: hand-detect / motion status.
    static let handDetect = uuid("1008")
}

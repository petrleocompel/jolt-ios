import Foundation

/// Every value here is a placeholder. Filling this in is the single blocker
/// on Shock Clock Max stimulus/alarm control — everything else (scanning,
/// pairing, standard GATT battery/device-info reads) already works.
///
/// ## What's missing
/// - The `ESFTag` byte-per-type mapping (`ESF/ESFTag.swift`)
/// - Message opcodes: handshake, MTU negotiation, time sync, battery report,
///   alarm CRUD (`SCMaxAlarmData`/`Dump`/`Deleted`/`NextAlarm`), triggers
///   dump/config, stopwatch, hand-detect, tune config, output/stimulus fire,
///   bulk file transfer framing (`SCMaxBulkMessageType`, `SCMaxFileType`,
///   `SCMaxLogSectorHeader`)
/// - Whether `SCMaxGATT.secondaryService` (`66657000-…`) is bulk transfer,
///   ANCS, or something else
///
/// These are compiled into AArch64 machine code in `libapp.so` — not visible
/// via string/manifest inspection. Recovering them needs a byte-level trace.
///
/// ## Capture procedure (Android, no root required for HCI snoop)
/// 1. On the Android test device: Settings → System → Developer options →
///    enable "Bluetooth HCI snoop log".
/// 2. Open the official Pavlok Android app, connect to a real Shock Clock
///    Max, and exercise one feature at a time (pair → read battery → fire a
///    zap at fixed intensity → set an alarm → delete it), pausing briefly
///    between each so the log is easy to segment.
/// 3. Pull the log: `adb bugreport` (log lands under
///    `FS/data/misc/bluetooth/logs/btsnoop_hci.log`), or on newer Android
///    pull directly from that path with `adb pull`.
/// 4. Open in Wireshark, filter `btatt`, follow the ATT writes/notifications
///    on handles matching `66651001`/`66651002`. Each payload is one ESF
///    message: first byte(s) are the tag/opcode, rest is LEB128-length-
///    prefixed payload per `ESFCodec`.
/// 5. Cross-reference byte patterns against the known model names in
///    `docs/RE-FINDINGS.md` §3 (e.g. a fixed-size payload sent right after
///    connect is almost certainly the handshake; a payload whose length
///    matches `intensity + repetitions + kind` sent when you tap zap in the
///    app is the stimulus/output command).
/// 6. Update `ESFTag` and add the recovered opcodes here, then implement the
///    corresponding methods in `SCMaxDeviceController`.
enum SCMaxProtocolMap {
    /// Placeholder — real handshake message not recovered.
    static let handshakeOpcode: UInt8? = nil
    /// Placeholder — real "fire stimulus" opcode not recovered.
    static let fireStimulusOpcode: UInt8? = nil
}

import Foundation

/// The device's answer to "what is every button currently set to?".
///
/// A plain GATT read of the setup characteristic does **not** answer that —
/// the firmware's read-authorize handler replies with a single status byte
/// from its own state block (`0x2FAD4`), which is why `readRawButtonConfig`
/// is a diagnostic and not a config read. The real query is the command
/// `01 01` written to `7001`, after which the device pushes the config back
/// as a burst of *notifications on that same characteristic*, driven by the
/// report state machine at `0x2F07C`.
///
/// What that machine emits, from the disassembly:
///
/// - a 3-byte **header** `[0xE0 | kind, param, 0x01]` (built at `0x2F0EC`:
///   the queued type is masked with `0x7F` and or-ed with `0xE0`), and
/// - **record frames** carrying a button's raw action record, whose length
///   the machine takes from the very same `action_size` helper the write path
///   uses (`0x2F130` → `0x225AC`), after substituting the firmware default
///   when a button has no stored record.
///
/// The sub-state counter that walks the buttons (`0x2F194`:
/// `records + 6 * (n - 1)`) runs `1...6`, i.e. the same button numbering as a
/// write. Which is why `param` above is read as the button.
///
/// **What is not pinned down** is the exact framing *around* each record: the
/// machine copies a leading byte from its own state before the payload
/// (`0x2F1CC`), and without a live capture it can't be said for certain
/// whether that byte is always present on the wire. So the parse below is
/// deliberately tolerant — it accepts a frame that is already a well-formed
/// record, and otherwise retries after dropping one leading byte — and every
/// frame is kept verbatim in `frames` so a real device can settle it.
struct ButtonConfigReport: Equatable {
    /// Decoded per-button records, for the buttons the report covered.
    var records: [DeviceButtonSlot: ButtonActionRecord] = [:]
    /// Every frame received, in arrival order. The source of truth when the
    /// decode below disagrees with hardware.
    var frames: [Data] = []
    /// Frames the parse could not attribute to a button.
    var unparsed: [Data] = []

    var isEmpty: Bool { frames.isEmpty }

    /// The action each covered button is set to, dropping anything that
    /// decoded to an unrecognised record.
    var actions: [DeviceButtonSlot: ButtonAction] {
        records.compactMapValues(\.action)
    }

    /// Builds a report from the notification frames collected after the query.
    static func parse(frames: [Data]) -> ButtonConfigReport {
        var report = ButtonConfigReport()
        report.frames = frames
        var currentSlot: DeviceButtonSlot?

        for frame in frames {
            if let button = headerButton(in: frame) {
                // A header with a button byte outside 1...6 is a section of
                // the report that isn't per-button config (the machine also
                // reports timers and other state); stop attributing records
                // until the next header we understand.
                currentSlot = DeviceButtonSlot(wireValue: button)
                continue
            }
            guard let slot = currentSlot, let record = record(in: frame) else {
                report.unparsed.append(frame)
                continue
            }
            report.records[slot] = record
        }
        return report
    }

    /// `[0xE0 | kind, button, 0x01]`.
    private static func headerButton(in frame: Data) -> UInt8? {
        guard frame.count == 3 else { return nil }
        let base = frame.startIndex
        guard frame[base] & 0xF0 == 0xE0, frame[base + 2] == 0x01 else { return nil }
        return frame[base + 1]
    }

    /// Reads a record out of a frame, tolerating one leading framing byte.
    ///
    /// A frame that already reads as a well-formed record is taken at face
    /// value; only one that doesn't is retried a byte in. The two readings
    /// genuinely collide when the framing byte is itself a valid action
    /// (`06 10 00` is both "toggle candle" and a framed `findMyPhone`), and
    /// nothing short of a live capture can settle that — so the greedy
    /// reading wins and the raw frame stays in `frames` to be argued with.
    private static func record(in frame: Data) -> ButtonActionRecord? {
        if let exact = wellFormedRecord(Data(frame)) { return exact }
        guard frame.count > 1 else { return nil }
        return wellFormedRecord(Data(frame.dropFirst()))
    }

    /// A frame is a record when its first byte is an action the firmware has
    /// a length for, and the frame is at least that long.
    private static func wellFormedRecord(_ bytes: Data) -> ButtonActionRecord? {
        guard let action = bytes.first else { return nil }
        let length = ButtonActionRecord.length(forAction: action)
        guard length > 0, bytes.count >= length else { return nil }
        return ButtonActionRecord(bytes: bytes.prefix(length))
    }
}

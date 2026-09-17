import Foundation

/// The device's own representation of "what this button does": a small
/// variable-length record whose first byte is the action and whose length is
/// fixed *per action*.
///
/// Both halves are ground truth from the firmware, not inference. The length
/// rule is `action_size` at `0x225AC` in `pavlok.bin` 6.8.0, a compare-chain
/// (not a table) transcribed byte for byte in `length(forAction:)` below. The
/// firmware consults exactly this function twice: once to reject a write
/// whose tail is too short (`set_action`, `0x2F3D8`), and once to decide how
/// many bytes to emit per button in the config report (`0x2F130`). Getting it
/// wrong in either direction is what made button config look dead — a
/// `findMyPhone` written as three bytes instead of four is refused outright
/// and the button silently keeps its old action.
///
/// See `docs/RE-FINDINGS.md` §3 and `jolt-firmware/docs/04-device-event-protocol.md`.
struct ButtonActionRecord: Equatable {
    /// Raw record bytes, action byte first.
    let bytes: Data

    init(bytes: Data) {
        self.bytes = bytes
    }

    var actionByte: UInt8? { bytes.first }

    /// How long a record for `action` is, *including* the action byte.
    ///
    /// `0` means the firmware has no length for it and rejects the write
    /// outright — that is how 6.8.0 treats `0x13` (`toggleSleepTracking`)
    /// and everything above `0x12` other than `0xFF`.
    ///
    /// Transcribed from the compare-chain at `0x225AC`; the odd-looking
    /// "everything else ≤ 0x12 is 1" fallback is the chain's own default, not
    /// a simplification.
    static func length(forAction action: UInt8) -> Int {
        if let explicit = explicitLengths[action] { return explicit }
        // The chain's own fallback: everything else at or below `0x12` is a
        // bare one-byte action, and everything above it is unknown and
        // refused. `0xFF` escapes the ceiling only because it is listed above.
        return action <= 0x12 ? 1 : 0
    }

    /// The actions the compare-chain names outright, with their record length.
    private static let explicitLengths: [UInt8: Int] = [
        0x01: 6,   // vibrate
        0x02: 6,   // beep
        0x03: 3,   // zap
        0x05: 2,
        0x0B: 5,
        0x0C: 5,
        0x0E: 3,
        0x10: 2,   // findMyPhone
        0x11: 4,   // stopwatch / timer
        0x12: 3,
        0xFF: 1    // disabled
    ]

    /// Whether fw 6.8.0 will accept a write carrying this action byte.
    static func isWritable(action: UInt8) -> Bool { length(forAction: action) > 0 }

    /// The action this record encodes, or `nil` when the bytes don't match
    /// anything recovered.
    ///
    /// `stopWatch` and `timer` deliberately share action byte `0x11` and are
    /// told apart by the record's last byte — that distinction lives in the
    /// payload, not in the action byte, which is why this can't be a plain
    /// byte→case map.
    var action: ButtonAction? {
        guard let actionByte else { return nil }
        switch actionByte {
        case 0x00: return .defaultAction
        case 0x01: return .vibrate
        case 0x02: return .beep
        case 0x03: return .zap
        case 0x06: return .toggleCandle
        case 0x07: return .nextTune
        case 0x08: return .airplaneMode
        case 0x0D: return .doNotDisturb
        case 0x10: return .findMyPhone
        case 0x11: return bytes.count >= 4 && bytes[bytes.startIndex + 3] == 0x02 ? .timer : .stopWatch
        case 0x13: return .toggleSleepTracking
        case 0xFF: return .disabled
        default: return nil
        }
    }

    /// Space-separated upper-hex, for the diagnostics readout.
    var hexString: String {
        bytes.isEmpty ? "(empty)" : bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

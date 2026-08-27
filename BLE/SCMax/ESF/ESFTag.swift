import Foundation

/// Tag byte for each `ESFValue` case, written before its payload.
///
/// ⚠️ PLACEHOLDER VALUES. The real tag bytes are compiled into
/// `libapp.so` machine code and were not recoverable by string analysis —
/// see `docs/RE-FINDINGS.md`. These placeholders make the codec internally
/// consistent (round-trips with itself and passes `JoltTests`), but a
/// real Shock Clock Max will not recognize messages built this way until
/// this table is replaced with values read from an HCI snoop log of the
/// official Pavlok app talking to real hardware. See `ProtocolMap.swift`
/// for the capture procedure.
enum ESFTag: UInt8 {
    case null = 0x00
    case bool = 0x01
    case int = 0x02
    case string = 0x03
    case fixBytes = 0x04
    case array = 0x05
    case list = 0x06
    case map = 0x07
}

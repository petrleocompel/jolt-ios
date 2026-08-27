import Foundation

/// The value model of Pavlok's "ESF" wire format used by Shock Clock Max,
/// reconstructed from the Dart source paths left in the Android binary:
/// `esf_int`, `esf_bool`, `esf_string`, `esf_array`, `esf_list`, `esf_map`,
/// `esf_null`, `esf_fix_bytes`. It reads as a small self-describing,
/// LEB128-length-prefixed TLV format, structurally similar to CBOR/MessagePack.
///
/// The distinction between `.array` and `.list` in the original source is
/// not recovered — kept as two cases so a real capture can tell us apart
/// (likely: `array` = fixed-count homogeneous, `list` = variable-length).
indirect enum ESFValue: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case string(String)
    case fixBytes(Data)
    case array([ESFValue])
    case list([ESFValue])
    case map([String: ESFValue])
}

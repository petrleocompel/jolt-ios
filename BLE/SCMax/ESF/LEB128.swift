import Foundation

/// Unsigned LEB128 varint — confirmed as the base integer encoding via
/// `leb_128_parser.dart` in the Android snapshot. Standard 7-bits-per-byte,
/// continuation bit in the high bit, little-endian group order.
enum LEB128 {
    enum DecodeError: Error {
        case truncated
        case overflow
    }

    static func encode(_ value: UInt64) -> [UInt8] {
        var remaining = value
        var bytes: [UInt8] = []
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while remaining != 0
        return bytes
    }

    /// Decodes one varint starting at `offset`, returns the value and the
    /// number of bytes consumed.
    static func decode(_ bytes: [UInt8], at offset: Int) throws -> (value: UInt64, length: Int) {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = offset
        while true {
            guard index < bytes.count else { throw DecodeError.truncated }
            let byte = bytes[index]
            index += 1
            guard shift < 64 else { throw DecodeError.overflow }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return (result, index - offset)
    }
}

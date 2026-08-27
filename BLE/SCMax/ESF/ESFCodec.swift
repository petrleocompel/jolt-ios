import Foundation

/// Encodes/decodes `ESFValue` trees to bytes using LEB128 varints for all
/// lengths and integers. See `ESFTag` for the caveat on tag byte values.
enum ESFCodec {
    enum DecodeError: Error {
        case unknownTag(UInt8)
        case malformedString
        case truncated
    }

    static func encode(_ value: ESFValue) -> [UInt8] {
        switch value {
        case .null:
            return [ESFTag.null.rawValue]

        case .bool(let flag):
            return [ESFTag.bool.rawValue, flag ? 1 : 0]

        case .int(let number):
            return [ESFTag.int.rawValue] + LEB128.encode(zigZagEncode(number))

        case .string(let text):
            let utf8 = Array(text.utf8)
            return [ESFTag.string.rawValue] + LEB128.encode(UInt64(utf8.count)) + utf8

        case .fixBytes(let data):
            return [ESFTag.fixBytes.rawValue] + LEB128.encode(UInt64(data.count)) + Array(data)

        case .array(let elements):
            return encodeSequence(tag: .array, elements: elements)

        case .list(let elements):
            return encodeSequence(tag: .list, elements: elements)

        case .map(let pairs):
            return encodeMap(pairs)
        }
    }

    private static func encodeSequence(tag: ESFTag, elements: [ESFValue]) -> [UInt8] {
        var bytes = [tag.rawValue] + LEB128.encode(UInt64(elements.count))
        for element in elements { bytes += encode(element) }
        return bytes
    }

    private static func encodeMap(_ pairs: [String: ESFValue]) -> [UInt8] {
        var bytes = [ESFTag.map.rawValue] + LEB128.encode(UInt64(pairs.count))
        for (key, value) in pairs.sorted(by: { $0.key < $1.key }) {
            bytes += encode(.string(key))
            bytes += encode(value)
        }
        return bytes
    }

    static func decode(_ bytes: [UInt8]) throws -> ESFValue {
        var offset = 0
        let value = try decodeValue(bytes, offset: &offset)
        return value
    }

    private static func decodeValue(_ bytes: [UInt8], offset: inout Int) throws -> ESFValue {
        guard offset < bytes.count else { throw DecodeError.truncated }
        let tagByte = bytes[offset]
        offset += 1
        guard let tag = ESFTag(rawValue: tagByte) else { throw DecodeError.unknownTag(tagByte) }

        switch tag {
        case .null:
            return .null

        case .bool:
            guard offset < bytes.count else { throw DecodeError.truncated }
            defer { offset += 1 }
            return .bool(bytes[offset] != 0)

        case .int:
            let (raw, length) = try LEB128.decode(bytes, at: offset)
            offset += length
            return .int(zigZagDecode(raw))

        case .string:
            return .string(try decodeString(bytes, offset: &offset))

        case .fixBytes:
            let count = try readLength(bytes, offset: &offset)
            let slice = try consumeBytes(count, from: bytes, offset: &offset)
            return .fixBytes(Data(slice))

        case .array, .list:
            let elements = try decodeElements(bytes, offset: &offset)
            return tag == .array ? .array(elements) : .list(elements)

        case .map:
            return .map(try decodeMap(bytes, offset: &offset))
        }
    }

    private static func decodeString(_ bytes: [UInt8], offset: inout Int) throws -> String {
        let count = try readLength(bytes, offset: &offset)
        let slice = try consumeBytes(count, from: bytes, offset: &offset)
        guard let text = String(bytes: slice, encoding: .utf8) else { throw DecodeError.malformedString }
        return text
    }

    private static func decodeElements(_ bytes: [UInt8], offset: inout Int) throws -> [ESFValue] {
        let count = try readLength(bytes, offset: &offset)
        var elements: [ESFValue] = []
        elements.reserveCapacity(count)
        for _ in 0..<count {
            elements.append(try decodeValue(bytes, offset: &offset))
        }
        return elements
    }

    private static func decodeMap(_ bytes: [UInt8], offset: inout Int) throws -> [String: ESFValue] {
        let count = try readLength(bytes, offset: &offset)
        var pairs: [String: ESFValue] = [:]
        for _ in 0..<count {
            guard case .string(let key) = try decodeValue(bytes, offset: &offset) else {
                throw DecodeError.malformedString
            }
            pairs[key] = try decodeValue(bytes, offset: &offset)
        }
        return pairs
    }

    private static func consumeBytes(_ count: Int, from bytes: [UInt8], offset: inout Int) throws -> ArraySlice<UInt8> {
        guard offset + count <= bytes.count else { throw DecodeError.truncated }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }

    private static func readLength(_ bytes: [UInt8], offset: inout Int) throws -> Int {
        let (raw, length) = try LEB128.decode(bytes, at: offset)
        offset += length
        return Int(raw)
    }

    /// Standard zig-zag mapping so small negative numbers stay small varints.
    private static func zigZagEncode(_ value: Int64) -> UInt64 {
        UInt64(bitPattern: (value << 1) ^ (value >> 63))
    }

    private static func zigZagDecode(_ value: UInt64) -> Int64 {
        Int64(bitPattern: (value >> 1)) ^ -Int64(bitPattern: value & 1)
    }
}

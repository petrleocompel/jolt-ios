import XCTest
@testable import Jolt

/// These confirm the codec is internally consistent (round-trips its own
/// output) — they do NOT confirm compatibility with a real Shock Clock Max.
/// See `BLE/SCMax/ESFTag.swift` for why.
final class ESFCodecTests: XCTestCase {
    func testRoundTripsNull() throws {
        try assertRoundTrip(.null)
    }

    func testRoundTripsBool() throws {
        try assertRoundTrip(.bool(true))
        try assertRoundTrip(.bool(false))
    }

    func testRoundTripsPositiveAndNegativeInts() throws {
        try assertRoundTrip(.int(0))
        try assertRoundTrip(.int(42))
        try assertRoundTrip(.int(-42))
        try assertRoundTrip(.int(Int64.max))
        try assertRoundTrip(.int(Int64.min))
    }

    func testRoundTripsString() throws {
        try assertRoundTrip(.string("hello ESF"))
        try assertRoundTrip(.string(""))
    }

    func testRoundTripsFixBytes() throws {
        try assertRoundTrip(.fixBytes(Data([0x01, 0x02, 0x03, 0xFF])))
    }

    func testRoundTripsNestedArrayAndMap() throws {
        let value = ESFValue.map([
            "kind": .string("zap"),
            "intensity": .int(30),
            "repetitions": .int(1),
            "history": .array([.int(1), .int(2), .int(3)])
        ])
        try assertRoundTrip(value)
    }

    func testDecodeThrowsOnUnknownTag() {
        XCTAssertThrowsError(try ESFCodec.decode([0xEE])) { error in
            guard case ESFCodec.DecodeError.unknownTag(0xEE) = error else {
                return XCTFail("Expected unknownTag, got \(error)")
            }
        }
    }

    private func assertRoundTrip(_ value: ESFValue, file: StaticString = #filePath, line: UInt = #line) throws {
        let encoded = ESFCodec.encode(value)
        let decoded = try ESFCodec.decode(encoded)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }
}

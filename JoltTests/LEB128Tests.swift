import XCTest
@testable import Jolt

final class LEB128Tests: XCTestCase {
    func testRoundTripSmallValues() throws {
        for value: UInt64 in [0, 1, 63, 64, 127, 128, 300] {
            let encoded = LEB128.encode(value)
            let (decoded, length) = try LEB128.decode(encoded, at: 0)
            XCTAssertEqual(decoded, value)
            XCTAssertEqual(length, encoded.count)
        }
    }

    func testEncodesSingleByteForValuesUnder128() {
        XCTAssertEqual(LEB128.encode(0), [0x00])
        XCTAssertEqual(LEB128.encode(127), [0x7F])
    }

    func testEncodesMultiByteForValuesAtOrAbove128() {
        XCTAssertEqual(LEB128.encode(128), [0x80, 0x01])
        XCTAssertEqual(LEB128.encode(300), [0xAC, 0x02])
    }

    func testDecodeThrowsOnTruncatedInput() {
        XCTAssertThrowsError(try LEB128.decode([0x80], at: 0)) { error in
            guard case LEB128.DecodeError.truncated = error else {
                return XCTFail("Expected .truncated, got \(error)")
            }
        }
    }

    func testDecodeAtOffsetSkipsPrecedingBytes() throws {
        let bytes: [UInt8] = [0xFF, 0x00, 0x01]
        let (value, length) = try LEB128.decode(bytes, at: 1)
        XCTAssertEqual(value, 0)
        XCTAssertEqual(length, 1)
    }
}

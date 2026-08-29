import XCTest
@testable import Jolt

final class PokeTriggerTests: XCTestCase {
    private let charA = "156E2000-A300-4FEA-897B-86F698D74461"
    private let charB = "156E2002-A300-4FEA-897B-86F698D74461"

    private func event(_ char: String, _ bytes: [UInt8]) -> DeviceEvent {
        DeviceEvent(serviceUUID: charA, characteristicUUID: char, data: Data(bytes))
    }

    private func learned(mode: PokeTrigger.MatchMode = .exact, bytes: [UInt8], char: String) -> PokeTrigger {
        var t = PokeTrigger.default
        t.isEnabled = true
        t.targetFriendID = UUID()
        t.learnedCharacteristicUUID = char
        t.learnedBytes = Data(bytes)
        t.matchMode = mode
        return t
    }

    func testExactMatchRequiresIdenticalBytesAndCharacteristic() {
        let trigger = learned(bytes: [0x01, 0x02, 0x03], char: charB)
        XCTAssertTrue(trigger.matches(event(charB, [0x01, 0x02, 0x03])))
        XCTAssertFalse(trigger.matches(event(charB, [0x01, 0x02])))        // different bytes
        XCTAssertFalse(trigger.matches(event(charA, [0x01, 0x02, 0x03])))  // different characteristic
    }

    func testCharacteristicComparisonIsCaseInsensitive() {
        let trigger = learned(bytes: [0xAB], char: charB.lowercased())
        XCTAssertTrue(trigger.matches(event(charB.uppercased(), [0xAB])))
    }

    func testPrefixModeToleratesTrailingBytes() {
        let trigger = learned(mode: .prefix, bytes: [0x0A, 0x0B], char: charB)
        XCTAssertTrue(trigger.matches(event(charB, [0x0A, 0x0B, 0x99])))   // trailing counter
        XCTAssertTrue(trigger.matches(event(charB, [0x0A, 0x0B])))
        XCTAssertFalse(trigger.matches(event(charB, [0x0A])))              // shorter than prefix
        XCTAssertFalse(trigger.matches(event(charB, [0x0B, 0x0A])))        // wrong order
    }

    func testIsArmedNeedsEnabledFriendAndLearnedGesture() {
        var t = PokeTrigger.default
        XCTAssertFalse(t.isArmed)                       // default: nothing set
        t.isEnabled = true
        XCTAssertFalse(t.isArmed)                       // no friend, no gesture
        t.targetFriendID = UUID()
        XCTAssertFalse(t.isArmed)                       // still no gesture
        t.learnedBytes = Data([0x01])
        XCTAssertTrue(t.isArmed)
        t.isEnabled = false
        XCTAssertFalse(t.isArmed)                       // disabled overrides
    }

    func testDisabledTriggerNeverArms() {
        var t = learned(bytes: [0x01], char: charB)
        t.isEnabled = false
        XCTAssertFalse(t.isArmed)
    }

    func testTriggerSurvivesJSONRoundTrip() throws {
        let t = learned(mode: .prefix, bytes: [0xDE, 0xAD, 0xBE, 0xEF], char: charB)
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(PokeTrigger.self, from: data)
        XCTAssertEqual(t, decoded)
    }
}

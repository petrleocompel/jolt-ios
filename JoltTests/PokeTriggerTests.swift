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
        XCTAssertTrue(trigger.matches(event(charB, [0x0A])))               // same event type
        XCTAssertFalse(trigger.matches(event(charB, [0x0B, 0x0A])))        // different event type
    }

    /// The case the whole mode exists for, and the one it used to fail: a
    /// gesture is learned from a *whole* captured frame, so the changing state
    /// bytes after the event type are baked into the learned copy. Comparing
    /// the event type alone is the only comparison that can tolerate that.
    func testPrefixModeToleratesAChangingTailInTheLearnedFrame() {
        let trigger = learned(mode: .prefix, bytes: [0x0C, 0x01, 0x5A], char: charB)
        XCTAssertTrue(trigger.matches(event(charB, [0x0C, 0x01, 0x5B])))
        XCTAssertTrue(trigger.matches(event(charB, [0x0C, 0x00, 0x00])))
        XCTAssertFalse(trigger.matches(event(charB, [0x04, 0x01, 0x5A])))  // different event
    }

    // MARK: Decoded press matching

    private func slotTrigger(_ slot: DeviceButtonSlot) -> PokeTrigger {
        var t = PokeTrigger.default
        t.isEnabled = true
        t.targetFriendID = UUID()
        t.buttonSlot = slot
        return t
    }

    /// The device announces the press as a find-my-phone event, and the
    /// trailing state bytes differ press to press (the toggle alternates), so
    /// matching has to key off the event type alone.
    func testConfiguredPressMatchesRegardlessOfTrailingBytes() {
        let trigger = slotTrigger(.topLong)
        XCTAssertTrue(trigger.matches(event(charB, [0x0C, 0x01, 0x7F])))
        XCTAssertTrue(trigger.matches(event(charB, [0x0C, 0x00, 0x00])))
        XCTAssertTrue(trigger.matches(event(charB, [0x0C])))
        XCTAssertFalse(trigger.matches(event(charB, [0x04, 0x01, 0x00])))  // another device event
        XCTAssertFalse(trigger.matches(event(charA, [0x0C, 0x01, 0x7F])))  // wrong characteristic
        XCTAssertFalse(trigger.matches(event(charB, [])))                  // empty frame
    }

    func testConfiguredPressWinsOverAStaleLearnedSignature() {
        var trigger = slotTrigger(.middle)
        trigger.learnedCharacteristicUUID = charB
        trigger.learnedBytes = Data([0x09, 0x09, 0x09])
        XCTAssertTrue(trigger.matches(event(charB, [0x0C, 0x01, 0x00])))
        XCTAssertFalse(trigger.matches(event(charB, [0x09, 0x09, 0x09])))
    }

    func testEventsCharacteristicIsRecognisedInBluetoothBaseForm() {
        // What a real Pavlok reports: a 16-bit characteristic inside a
        // 128-bit vendor service, so it arrives expanded against the
        // Bluetooth base, not the vendor base.
        let shortForm = "00002002-0000-1000-8000-00805F9B34FB"
        XCTAssertTrue(event(shortForm, [0x0C, 0x01, 0x00]).isFindMyPhoneEvent)
    }

    /// Frames on any other characteristic are not events, whatever byte 0 is —
    /// the app subscribes to every notifying characteristic, so this guard is
    /// the only thing stopping an unrelated `0C` from poking someone.
    func testOnlyTheEventsCharacteristicDecodes() {
        XCTAssertNil(event(charA, [0x0C, 0x01, 0x00]).eventType)
        XCTAssertFalse(event(charA, [0x0C, 0x01, 0x00]).isFindMyPhoneEvent)
    }

    func testArmedWithAButtonButNoLearnedSignature() {
        var t = PokeTrigger.default
        t.isEnabled = true
        t.targetFriendID = UUID()
        XCTAssertFalse(t.isArmed)
        t.buttonSlot = .top
        XCTAssertTrue(t.isArmed)
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

    /// Old stored triggers predate `buttonSlot`; decoding must not fail on a
    /// payload that has no such key, or every existing user silently loses
    /// their configured trigger on update.
    func testDecodingToleratesPayloadWithoutButtonSlot() throws {
        let json = """
        {"isEnabled":true,"stimulus":{"kind":"vibe","intensity":30,"repetitions":1},
         "matchMode":"exact","debounceSeconds":2}
        """
        let decoded = try JSONDecoder().decode(PokeTrigger.self, from: Data(json.utf8))
        XCTAssertNil(decoded.buttonSlot)
        XCTAssertTrue(decoded.isEnabled)
    }

    func testTriggerSurvivesJSONRoundTrip() throws {
        var t = learned(mode: .prefix, bytes: [0xDE, 0xAD, 0xBE, 0xEF], char: charB)
        t.buttonSlot = .bottomLong
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(PokeTrigger.self, from: data)
        XCTAssertEqual(t, decoded)
    }
}

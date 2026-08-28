import CoreBluetooth
import XCTest
@testable import Jolt

final class LegacyProtocolStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "LegacyProtocolStoreTests-\(UUID().uuidString)")
    }

    func testFallsBackToTheInferredDefaultMapping() {
        let store = LegacyProtocolStore(defaults: defaults)
        XCTAssertEqual(store.characteristic(for: .zap), LegacyGATT.zap)
        XCTAssertEqual(store.characteristic(for: .vibe), LegacyGATT.vibration)
        XCTAssertEqual(store.characteristic(for: .beep), LegacyGATT.beep)
        XCTAssertFalse(store.hasOverride(for: .zap))
    }

    func testOverrideAppliesToOnlyTheKindItWasSetFor() {
        let store = LegacyProtocolStore(defaults: defaults)
        store.setCharacteristic(CBUUID(string: "1006"), for: .beep)

        XCTAssertEqual(store.characteristic(for: .beep), CBUUID(string: "1006"))
        XCTAssertTrue(store.hasOverride(for: .beep))
        XCTAssertEqual(store.characteristic(for: .zap), LegacyGATT.zap)
        XCTAssertFalse(store.hasOverride(for: .zap))
    }

    func testResetRestoresEveryDefault() {
        let store = LegacyProtocolStore(defaults: defaults)
        store.setCharacteristic(CBUUID(string: "1008"), for: .zap)
        store.reset()
        XCTAssertEqual(store.characteristic(for: .zap), LegacyGATT.zap)
    }

    func testStringAccessorsUseTheShortFormThatGATTDumpsCarry() {
        // `CBUUID.uuidString` collapses Bluetooth-base UUIDs to their 16-bit
        // form, which is what the picker compares against.
        let store = LegacyProtocolStore(defaults: defaults)
        XCTAssertEqual(store.characteristicUUIDString(for: .zap), "1002")

        store.setCharacteristicUUIDString("1005", for: .zap)
        XCTAssertEqual(store.characteristic(for: .zap), LegacyGATT.beep)
    }
}

final class LegacyStimulusPayloadTests: XCTestCase {
    func testPayloadIsRepetitionsThenIntensity() {
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)
        )
        XCTAssertEqual([UInt8](payload), [0x01, 0x14])
    }

    func testPayloadCarriesNoOpcodeByte() {
        // Each stimulus kind has its own characteristic, so the same
        // intensity and count produce identical bytes regardless of kind.
        let zap = LegacyDeviceController.payload(for: StimulusConfig(kind: .zap, intensity: 50, repetitions: 2))
        let beep = LegacyDeviceController.payload(for: StimulusConfig(kind: .beep, intensity: 50, repetitions: 2))
        XCTAssertEqual(zap, beep)
        XCTAssertEqual(zap.count, 2)
    }

    func testClampedValuesStayInByteRange() {
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .vibe, intensity: 100, repetitions: 5)
        )
        XCTAssertEqual([UInt8](payload), [0x05, 0x64])
    }
}

final class ProtocolLabHexParsingTests: XCTestCase {
    func testParsesSpacedAndUnspacedHex() {
        XCTAssertEqual(ProtocolLabView.parseHex("14 01"), [0x14, 0x01])
        XCTAssertEqual(ProtocolLabView.parseHex("1401"), [0x14, 0x01])
        XCTAssertEqual(ProtocolLabView.parseHex("0x14 0x01"), [0x14, 0x01])
        XCTAssertEqual(ProtocolLabView.parseHex("ff"), [0xFF])
    }

    func testRejectsMalformedInput() {
        XCTAssertNil(ProtocolLabView.parseHex(""))
        XCTAssertNil(ProtocolLabView.parseHex("1"))
        XCTAssertNil(ProtocolLabView.parseHex("14 0"))
        XCTAssertNil(ProtocolLabView.parseHex("zz"))
    }
}

final class CBUUIDCanonicalTests: XCTestCase {
    func testShortAndLongFormsOfTheSameUUIDMatch() {
        let short = CBUUID(string: "1002")
        let long = CBUUID(string: "00001002-0000-1000-8000-00805F9B34FB")

        // `CBUUID` itself compares equal across forms...
        XCTAssertEqual(short, long)
        // ...but `uuidString` does not normalise, which is the trap: anything
        // that compares UUIDs as text (a persisted override, a GATT dump row,
        // a string-keyed continuation map) sees two different values.
        XCTAssertNotEqual(short.uuidString, long.uuidString)
        XCTAssertEqual(short.canonicalString, long.canonicalString)
        XCTAssertTrue(short.matches(long))
    }

    func testCanonicalStringKeysAreInterchangeableInADictionary() {
        var map: [String: Int] = [:]
        map[CBUUID(string: "00001002-0000-1000-8000-00805F9B34FB").canonicalString] = 1
        XCTAssertEqual(map[CBUUID(string: "1002").canonicalString], 1)
    }

    func testCanonicalStringIsCaseInsensitiveAcrossInputForms() {
        XCTAssertTrue(CBUUID(string: "180a").matches(CBUUID(string: "0000180A-0000-1000-8000-00805f9b34fb")))
    }

    func testDistinctUUIDsDoNotMatch() {
        XCTAssertFalse(CBUUID(string: "1002").matches(CBUUID(string: "1003")))
        XCTAssertFalse(
            CBUUID(string: "66651001-39F4-11ED-92BD-832ABAC11AB4")
                .matches(CBUUID(string: "66651002-39F4-11ED-92BD-832ABAC11AB4"))
        )
    }

    func testVendorUUIDsRoundTripUnchanged() {
        let vendor = CBUUID(string: "66651001-39F4-11ED-92BD-832ABAC11AB4")
        XCTAssertEqual(vendor.canonicalString, "66651001-39F4-11ED-92BD-832ABAC11AB4")
    }
}

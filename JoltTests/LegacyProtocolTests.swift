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

    func testConfigServiceUsesTheVendorBaseNotTheBluetoothBase() {
        // Confirmed against a Pavlok 3 (fw 6.10.0): the service is
        // `156E1000-…`, and `1001` is a characteristic inside it. Treating
        // `1001` as the service is what made every write fail at lookup.
        XCTAssertEqual(LegacyGATT.service.uuidString, "156E1000-A300-4FEA-897B-86F698D74461")
        XCTAssertEqual(LegacyGATT.applicationService.uuidString, "156E2000-A300-4FEA-897B-86F698D74461")
        XCTAssertNotEqual(LegacyGATT.service, CBUUID(string: "1001"))
    }

    func testStimulusCharacteristicsAreOnesTheAndroidAppActuallyReferences() {
        // 1004 and 1007 exist on the device but appear nowhere in the binary,
        // so no stimulus output can be behind them.
        for kind in StimulusKind.allCases {
            XCTAssertTrue(
                LegacyGATT.configServiceCharacteristics.contains(LegacyGATT.defaultCharacteristic(for: kind)),
                "\(kind) maps outside the referenced config characteristics"
            )
        }
        XCTAssertFalse(LegacyGATT.configServiceCharacteristics.contains(CBUUID(string: "1004")))
        XCTAssertFalse(LegacyGATT.configServiceCharacteristics.contains(CBUUID(string: "1007")))
    }

    func testEachStimulusKindMapsToADistinctCharacteristic() {
        let mapped = StimulusKind.allCases.map { LegacyGATT.defaultCharacteristic(for: $0).uuidString }
        XCTAssertEqual(Set(mapped).count, StimulusKind.allCases.count)
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
        XCTAssertEqual(store.characteristicUUIDString(for: .zap), "1001")

        store.setCharacteristicUUIDString("1003", for: .zap)
        XCTAssertEqual(store.characteristic(for: .zap), LegacyGATT.beep)
    }
}

final class LegacyStimulusPayloadTests: XCTestCase {
    /// Exactly what a Pavlok 3 (fw 6.10.0) reports.
    private let zapConfig = Data([0x01, 0x0C, 0x23, 0x16, 0x16])
    private let vibeConfig = Data([0x01, 0x0C, 0x64, 0x16, 0x16])
    private let beepConfig = Data([0x01, 0x19])

    func testLevelGoesAtIndexTwoInTheFiveByteLayout() {
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1),
            existing: zapConfig
        )
        XCTAssertEqual([UInt8](payload!), [0x01, 0x0C, 0x14, 0x16, 0x16])
    }

    func testEveryOtherByteIsPreservedExactly() {
        // Index 1 is a bounded field that rejected 0x32 outright on real
        // hardware. Writing anything into fields we don't understand is how
        // an acknowledged write ends up doing nothing.
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .vibe, intensity: 60, repetitions: 4),
            existing: vibeConfig
        )!
        XCTAssertEqual(payload[0], vibeConfig[0])
        XCTAssertEqual(payload[1], vibeConfig[1])
        XCTAssertEqual(payload[3], vibeConfig[3])
        XCTAssertEqual(payload[4], vibeConfig[4])
        XCTAssertEqual(payload[2], 60)
    }

    func testLevelGoesAtIndexOneInTheTwoByteLayout() {
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .beep, intensity: 10, repetitions: 1),
            existing: beepConfig
        )
        XCTAssertEqual([UInt8](payload!), [0x01, 0x0A])
    }

    func testRepetitionsAreNotWrittenAnywhere() {
        // The count field has not been identified. Until it is, changing
        // repetitions must not alter a single byte.
        let one = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1), existing: zapConfig
        )
        let five = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 20, repetitions: 5), existing: zapConfig
        )
        XCTAssertEqual(one, five)
    }

    func testUnrecognisedLayoutsAreRefusedRatherThanScribbledOn() {
        for length in [0, 1, 3, 4, 6, 8] {
            XCTAssertNil(
                LegacyDeviceController.payload(
                    for: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1),
                    existing: Data(repeating: 0, count: length)
                ),
                "\(length)-byte layout should be refused"
            )
        }
        XCTAssertNil(
            LegacyDeviceController.payload(
                for: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1), existing: nil
            )
        )
    }

    func testPayloadLengthAlwaysMatchesTheDevice() {
        for existing in [zapConfig, vibeConfig, beepConfig] {
            let payload = LegacyDeviceController.payload(
                for: StimulusConfig(kind: .zap, intensity: 77, repetitions: 1), existing: existing
            )
            XCTAssertEqual(payload?.count, existing.count)
        }
    }

    func testIntensityIsClampedIntoAByte() {
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 100, repetitions: 1), existing: zapConfig
        )
        XCTAssertEqual(payload?[2], 100)
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

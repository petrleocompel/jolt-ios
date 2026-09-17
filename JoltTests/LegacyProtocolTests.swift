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

    func testServiceUUIDsMatchTheDecompiledConstants() {
        // Values read out of ble_uuids_constants.dart via blutter. The
        // numbering is not what it looks like: 156E5000 is the application
        // service and 156E0000 is the diagnostic one.
        XCTAssertEqual(LegacyGATT.service.uuidString, "156E1000-A300-4FEA-897B-86F698D74461")
        XCTAssertEqual(LegacyGATT.pavlokService.uuidString, "156E0000-A300-4FEA-897B-86F698D74461")
        XCTAssertEqual(LegacyGATT.notificationService.uuidString, "156E2000-A300-4FEA-897B-86F698D74461")
        XCTAssertEqual(LegacyGATT.applicationService.uuidString, "156E5000-A300-4FEA-897B-86F698D74461")
        XCTAssertEqual(LegacyGATT.firmwareService.uuidString, "156E6000-A300-4FEA-897B-86F698D74461")
        XCTAssertEqual(LegacyGATT.setupService.uuidString, "156E7000-A300-4FEA-897B-86F698D74461")
    }

    func testStimulusCharacteristicsMatchTheDecompiledConstants() {
        // kVibrationCaracUuid=1001, kBeepCaracUuid=1002, kZapCaracUuid=1003.
        // Zap is last. An earlier guess had zap first, which pointed "Beep"
        // at the zap output.
        XCTAssertEqual(LegacyGATT.characteristic(for: .vibe).uuidString, "1001")
        XCTAssertEqual(LegacyGATT.characteristic(for: .beep).uuidString, "1002")
        XCTAssertEqual(LegacyGATT.characteristic(for: .zap).uuidString, "1003")
    }

    func testEachStimulusKindMapsToADistinctCharacteristic() {
        let mapped = StimulusKind.allCases.map { LegacyGATT.characteristic(for: $0).uuidString }
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
        XCTAssertEqual(store.characteristicUUIDString(for: .zap), "1003")

        store.setCharacteristicUUIDString("1002", for: .zap)
        XCTAssertEqual(store.characteristic(for: .zap), LegacyGATT.beep)
    }
}

final class LegacyStimulusPayloadTests: XCTestCase {
    /// Exactly what a Pavlok 3 (fw 6.10.0) reports.
    private let vibeConfig = Data([0x01, 0x0C, 0x23, 0x16, 0x16])
    private let beepConfig = Data([0x01, 0x0C, 0x64, 0x16, 0x16])
    private let zapConfig = Data([0x01, 0x19])

    func testFireSetsBit7AndStoreSetsBit6() {
        // performZap adds 0x80, updateZap adds 0x40, to the same byte of the
        // same characteristic. Writing neither is what made every earlier
        // write acknowledged and inert.
        let fired = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 25, repetitions: 1),
            existing: zapConfig, command: .fire
        )!
        let stored = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 25, repetitions: 1),
            existing: zapConfig, command: .store
        )!
        XCTAssertEqual([UInt8](fired), [0x81, 0x19])
        XCTAssertEqual([UInt8](stored), [0x41, 0x19])
    }

    func testZapPayloadIsCountThenLevel() {
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .zap, intensity: 40, repetitions: 3),
            existing: zapConfig, command: .fire
        )!
        XCTAssertEqual([UInt8](payload), [0x83, 0x28])
    }

    func testFiveBytePayloadPreservesTheConstantAndIntervals() {
        // performMotor writes a literal 0x0C at index 1 and two encoded
        // interval bytes at 3 and 4. Those come from millisecond fields this
        // app doesn't expose, so they're carried through untouched.
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .vibe, intensity: 60, repetitions: 2),
            existing: vibeConfig, command: .fire
        )!
        XCTAssertEqual([UInt8](payload), [0x82, 0x0C, 0x3C, 0x16, 0x16])
    }

    func testBeepUsesTheSameFiveByteShape() {
        let payload = LegacyDeviceController.payload(
            for: StimulusConfig(kind: .beep, intensity: 100, repetitions: 1),
            existing: beepConfig, command: .fire
        )!
        XCTAssertEqual([UInt8](payload), [0x81, 0x0C, 0x64, 0x16, 0x16])
    }

    func testCountCanNeverCarryIntoTheCommandFlag() {
        // Count is masked to 6 bits: a large repetition count must not turn a
        // store into a fire, or vice versa.
        for reps in 1...100 {
            let payload = LegacyDeviceController.payload(
                for: StimulusConfig(kind: .zap, intensity: 10, repetitions: reps),
                existing: zapConfig, command: .store
            )!
            XCTAssertEqual(payload[0] & 0xC0, 0x40, "reps \(reps) corrupted the command flag")
        }
    }

    func testPayloadLengthAlwaysMatchesTheDevice() {
        for existing in [vibeConfig, beepConfig, zapConfig] {
            let payload = LegacyDeviceController.payload(
                for: StimulusConfig(kind: .zap, intensity: 77, repetitions: 1),
                existing: existing, command: .fire
            )
            XCTAssertEqual(payload?.count, existing.count)
        }
    }

    func testUnrecognisedLayoutsAreRefusedRatherThanScribbledOn() {
        for length in [0, 1, 3, 4, 6, 8] {
            XCTAssertNil(
                LegacyDeviceController.payload(
                    for: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1),
                    existing: Data(repeating: 0, count: length), command: .fire
                ),
                "\(length)-byte layout should be refused"
            )
        }
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

    func testFormatsAndShortensForTheExchangeLog() {
        XCTAssertEqual(ProtocolLabView.formatHex([0x01, 0x0A, 0x00, 0x3C]), "01 0A 00 3C")
        XCTAssertEqual(ProtocolLabView.shortUUID("156E1001-A300-4FEA-897B-86F698D74461"), "156E1001")
        XCTAssertEqual(ProtocolLabView.shortUUID("2A19"), "2A19")
    }

    func testLabelQualifiesOnlyAmbiguousShortUUIDs() {
        let a = GATTCharacteristicDump(serviceUUID: "156E1000-A300", uuid: "1001", properties: ["write"])
        let b = GATTCharacteristicDump(serviceUUID: "180F", uuid: "1001", properties: ["write"])
        let c = GATTCharacteristicDump(serviceUUID: "180F", uuid: "2A19", properties: ["write"])
        XCTAssertEqual(ProtocolLabView.label(for: a, among: [a, b, c]), "156E1000/1001")
        XCTAssertEqual(ProtocolLabView.label(for: c, among: [a, b, c]), "2A19")
    }
}

/// The Protocol lab's Mode picker has to reach CoreBluetooth; a write type
/// silently falling back to the inferred one would make the picker a lie.
@MainActor
final class RawWriteModeTests: XCTestCase {
    func testFakeRepositoryRecordsRequestedMode() async throws {
        let repository = FakeDeviceRepository()
        let viewModel = DeviceControlViewModel(repository: repository)
        try await viewModel.writeRaw(Data([0x01]), characteristicUUID: "1001", serviceUUID: "156E", mode: .withoutResponse)
        try await viewModel.writeRaw(Data([0x02]), characteristicUUID: "1002", serviceUUID: "156E", mode: .withResponse)
        XCTAssertEqual(repository.rawWrites.map(\.mode), [.withoutResponse, .withResponse])
        XCTAssertEqual(repository.rawWrites.first?.data, Data([0x01]))
    }

    func testFakeRepositoryRefusesRawWriteWithoutDevice() async {
        let repository = FakeDeviceRepository(startsPaired: false)
        do {
            try await repository.writeRaw(Data([0x01]), characteristicUUID: "1001", serviceUUID: "156E", mode: .withResponse)
            XCTFail("Expected notConnected")
        } catch {}
        XCTAssertTrue(repository.rawWrites.isEmpty)
    }

    func testModeRequiresMatchingDeclaredProperty() {
        XCTAssertEqual(RawWriteMode.withResponse.requiredProperty, "write")
        XCTAssertEqual(RawWriteMode.withoutResponse.requiredProperty, "writeNoResp")
    }

    func testCentralHonoursRequestedWriteType() {
        let both: CBCharacteristicProperties = [.write, .writeWithoutResponse]
        XCTAssertEqual(BluetoothCentralManager.writeType(requested: nil, properties: both), .withResponse)
        XCTAssertEqual(BluetoothCentralManager.writeType(requested: .withoutResponse, properties: both), .withoutResponse)
        XCTAssertEqual(BluetoothCentralManager.writeType(requested: .withResponse, properties: both), .withResponse)
        // A type the characteristic doesn't declare is refused, never
        // silently swapped for the other one.
        XCTAssertNil(BluetoothCentralManager.writeType(requested: .withoutResponse, properties: [.write]))
        XCTAssertNil(BluetoothCentralManager.writeType(requested: .withResponse, properties: [.writeWithoutResponse]))
        XCTAssertEqual(BluetoothCentralManager.writeType(requested: nil, properties: [.writeWithoutResponse]), .withoutResponse)
        XCTAssertNil(BluetoothCentralManager.writeType(requested: nil, properties: [.read]))
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

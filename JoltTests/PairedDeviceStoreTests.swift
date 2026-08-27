import XCTest
@testable import Jolt

final class PairedDeviceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PairedDeviceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testLoadReturnsNilWhenNothingSaved() {
        let store = PairedDeviceStore(defaults: defaults)
        XCTAssertNil(store.load())
    }

    func testSaveThenLoadRoundTrips() {
        let store = PairedDeviceStore(defaults: defaults)
        let id = UUID()
        store.save(peripheralIdentifier: id, name: "pavlok-3", family: .pavlok3)

        let loaded = store.load()
        XCTAssertEqual(loaded?.peripheralIdentifier, id)
        XCTAssertEqual(loaded?.name, "pavlok-3")
        XCTAssertEqual(loaded?.family, .pavlok3)
    }

    func testSaveOverwritesPreviousRecord() {
        let store = PairedDeviceStore(defaults: defaults)
        store.save(peripheralIdentifier: UUID(), name: "pavlok-2", family: .pavlok2)
        let secondID = UUID()
        store.save(peripheralIdentifier: secondID, name: "shock-clock-max", family: .shockClockMax)

        let loaded = store.load()
        XCTAssertEqual(loaded?.peripheralIdentifier, secondID)
        XCTAssertEqual(loaded?.family, .shockClockMax)
    }

    func testClearRemovesRecord() {
        let store = PairedDeviceStore(defaults: defaults)
        store.save(peripheralIdentifier: UUID(), name: "pavlok-3", family: .pavlok3)
        store.clear()
        XCTAssertNil(store.load())
    }
}

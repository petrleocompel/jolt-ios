import XCTest
@testable import Jolt

final class DeviceFamilyMatchingTests: XCTestCase {
    func testPavlok3IsNotClassifiedAsShockClockMax() {
        // Regression: `shockClockMax` used to list a bare "Pavlok" prefix and
        // matching iterated a `Set`, so a Pavlok 3 could be routed to the
        // SCMax controller — which throws `notImplemented` on every stimulus.
        XCTAssertEqual(DeviceFamily.matching(name: "pavlok-3"), .pavlok3)
        XCTAssertEqual(DeviceFamily.matching(name: "Pavlok-3"), .pavlok3)
    }

    func testLegacyFamiliesMatchTheirAdvertisedNames() {
        XCTAssertEqual(DeviceFamily.matching(name: "pavlok-2"), .pavlok2)
        XCTAssertEqual(DeviceFamily.matching(name: "Pavlok-1"), .pavlok2)
        XCTAssertEqual(DeviceFamily.matching(name: "ShockClockMax"), .shockClockMax)
    }

    func testUnsupportedPavlokProductsDoNotMatch() {
        XCTAssertNil(DeviceFamily.matching(name: "Pavlok-RingL"))
        XCTAssertNil(DeviceFamily.matching(name: "Pavlok-Smart-Ring"))
        XCTAssertNil(DeviceFamily.matching(name: "AirPods Pro"))
    }

    func testMatchingHonoursTheCandidateFilter() {
        XCTAssertNil(DeviceFamily.matching(name: "pavlok-3", in: [.pavlok2]))
        XCTAssertEqual(DeviceFamily.matching(name: "pavlok-3", in: [.pavlok3]), .pavlok3)
    }

    func testMatchingIsStableAcrossRepeatedCalls() {
        // The candidate set is a `Set`, whose iteration order is not defined.
        // Matching must not depend on it.
        let results = (0..<50).map { _ in DeviceFamily.matching(name: "pavlok-3", in: Set(DeviceFamily.allCases)) }
        XCTAssertEqual(Set(results), [.pavlok3])
    }
}

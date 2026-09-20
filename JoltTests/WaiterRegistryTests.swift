import XCTest
@testable import Jolt

/// The bookkeeping behind `BluetoothCentralManager`'s service and
/// characteristic discovery. Exercised with plain values rather than
/// continuations: the invariant under test is who gets woken, and getting it
/// wrong on the real thing means a task parked forever (which is how the
/// dashboard lost its battery readout).
@MainActor
final class WaiterRegistryTests: XCTestCase {
    private typealias Registry = WaiterRegistry<String, Int>

    func testTakeAllWakesEveryWaiterOnTheSameKey() {
        var registry = Registry()
        registry.add(1, token: Registry.Token(), for: "peripheral")
        registry.add(2, token: Registry.Token(), for: "peripheral")

        XCTAssertEqual(Set(registry.takeAll(for: "peripheral")), [1, 2])
        XCTAssertTrue(registry.isEmpty)
    }

    /// The regression this type exists for: a second waiter on one key used
    /// to replace the first, which was then never resumed.
    func testASecondWaiterDoesNotDisplaceTheFirst() {
        var registry = Registry()
        let first = Registry.Token()
        registry.add(1, token: first, for: "peripheral")
        registry.add(2, token: Registry.Token(), for: "peripheral")

        XCTAssertEqual(registry.take(first, for: "peripheral"), 1)
        XCTAssertEqual(registry.takeAll(for: "peripheral"), [2])
    }

    func testWaitersOnDifferentKeysAreIndependent() {
        var registry = Registry()
        registry.add(1, token: Registry.Token(), for: "a")
        registry.add(2, token: Registry.Token(), for: "b")

        XCTAssertEqual(registry.takeAll(for: "a"), [1])
        XCTAssertEqual(registry.takeAll(for: "b"), [2])
    }

    /// A timeout firing after the answer arrived must not resume anything —
    /// least of all somebody else's waiter, which is what the single-slot
    /// version did.
    func testTakingAnAlreadyAnsweredWaiterReturnsNil() {
        var registry = Registry()
        let token = Registry.Token()
        registry.add(1, token: token, for: "peripheral")
        _ = registry.takeAll(for: "peripheral")

        XCTAssertNil(registry.take(token, for: "peripheral"))
    }

    func testTakingOneWaiterLeavesTheOthersWaiting() {
        var registry = Registry()
        let timedOut = Registry.Token()
        registry.add(1, token: timedOut, for: "peripheral")
        registry.add(2, token: Registry.Token(), for: "peripheral")

        XCTAssertEqual(registry.take(timedOut, for: "peripheral"), 1)
        XCTAssertFalse(registry.isEmpty)
        XCTAssertEqual(registry.takeAll(for: "peripheral"), [2])
    }

    /// How a disconnect fails everything parked on the peripheral that went
    /// away, without touching waiters for any other one.
    func testTakeAllMatchingKeysLeavesNonMatchingWaiters() {
        var registry = Registry()
        registry.add(1, token: Registry.Token(), for: "gone/180A")
        registry.add(2, token: Registry.Token(), for: "gone/180F")
        registry.add(3, token: Registry.Token(), for: "other/180A")

        let failed = registry.takeAll { $0.hasPrefix("gone/") }

        XCTAssertEqual(Set(failed), [1, 2])
        XCTAssertEqual(registry.takeAll(for: "other/180A"), [3])
    }

    func testTakingTheLastWaiterEmptiesTheRegistry() {
        var registry = Registry()
        let token = Registry.Token()
        registry.add(1, token: token, for: "peripheral")

        XCTAssertEqual(registry.take(token, for: "peripheral"), 1)
        XCTAssertTrue(registry.isEmpty)
    }
}

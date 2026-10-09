import CryptoKit
import XCTest
@testable import Jolt

/// Key rotation (protocol C8): the current key, and the one it replaced for a
/// day, chosen by `kid`.
final class PayloadKeyStoreTests: XCTestCase {
    private let serverId = "srv_kzdvvj2umnduyauf35o36k6kw4"
    private var clock = Date(timeIntervalSince1970: 1_791_000_000)
    private lazy var store = PayloadKeyStore(service: "cz.peelco.jolt.tests.keyRotation") { [unowned self] in clock }

    override func tearDown() {
        store.remove(for: serverId)
        super.tearDown()
    }

    func testFindsTheCurrentKeyByItsKID() {
        let key = SymmetricKey(size: .bits256)
        XCTAssertTrue(store.save(key, for: serverId))

        XCTAssertEqual(kid(store.currentKey(for: serverId)), kid(key))
        XCTAssertEqual(kid(store.key(for: serverId, kid: kid(key))), kid(key))
        XCTAssertNil(store.key(for: serverId, kid: kid(SymmetricKey(size: .bits256))))
        XCTAssertNil(store.key(for: "srv_aaaaaaaaaaaaaaaaaaaaaaaaaa", kid: kid(key)))
    }

    func testKeepsTheReplacedKeyForADay() {
        let old = SymmetricKey(size: .bits256)
        let new = SymmetricKey(size: .bits256)
        store.save(old, for: serverId)
        store.save(new, for: serverId)

        XCTAssertEqual(kid(store.currentKey(for: serverId)), kid(new))
        XCTAssertEqual(kid(store.key(for: serverId, kid: kid(old))), kid(old))

        clock.addTimeInterval(PayloadKeyStore.previousKeyLifetime - 60)
        XCTAssertNotNil(store.key(for: serverId, kid: kid(old)))

        clock.addTimeInterval(120)
        XCTAssertNil(store.key(for: serverId, kid: kid(old)), "past a day, the previous key is gone")
        XCTAssertNotNil(store.key(for: serverId, kid: kid(new)))
    }

    /// Only the immediately previous key is kept.
    func testKeepsOnlyOnePreviousKey() {
        let first = SymmetricKey(size: .bits256)
        let second = SymmetricKey(size: .bits256)
        let third = SymmetricKey(size: .bits256)
        store.save(first, for: serverId)
        store.save(second, for: serverId)
        store.save(third, for: serverId)

        XCTAssertNil(store.key(for: serverId, kid: kid(first)))
        XCTAssertNotNil(store.key(for: serverId, kid: kid(second)))
        XCTAssertNotNil(store.key(for: serverId, kid: kid(third)))
    }

    /// Saving the same key again must not demote it.
    func testSavingTheCurrentKeyAgainKeepsNoPreviousKey() {
        let first = SymmetricKey(size: .bits256)
        let second = SymmetricKey(size: .bits256)
        store.save(first, for: serverId)
        store.save(second, for: serverId)
        store.save(second, for: serverId)

        XCTAssertNotNil(store.key(for: serverId, kid: kid(first)), "the earlier rotation's previous key survives")
        XCTAssertEqual(kid(store.currentKey(for: serverId)), kid(second))
    }

    func testRetiringTheCurrentKeyLeavesItAsThePreviousOne() {
        let key = SymmetricKey(size: .bits256)
        store.save(key, for: serverId)

        store.retireCurrentKey(for: serverId)

        XCTAssertNil(store.currentKey(for: serverId))
        XCTAssertNotNil(store.key(for: serverId, kid: kid(key)))
    }

    func testRemovingForgetsBothKeys() {
        let old = SymmetricKey(size: .bits256)
        let new = SymmetricKey(size: .bits256)
        store.save(old, for: serverId)
        store.save(new, for: serverId)

        store.remove(for: serverId)

        XCTAssertNil(store.currentKey(for: serverId))
        XCTAssertNil(store.key(for: serverId, kid: kid(old)))
        XCTAssertNil(store.key(for: serverId, kid: kid(new)))
    }

    private func kid(_ key: SymmetricKey?) -> String {
        key.map(PushEnvelope.keyID(for:)) ?? "none"
    }
}

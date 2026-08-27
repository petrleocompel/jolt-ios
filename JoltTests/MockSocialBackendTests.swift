import XCTest
@testable import Jolt

@MainActor
final class MockSocialBackendTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: PokeSettings.doNotDisturbKey)
    }

    private func signedInBackend() async throws -> (MockSocialBackend, [Friend]) {
        let backend = MockSocialBackend(deviceRepository: FakeDeviceRepository())
        try await backend.signUp(email: "me@example.com", password: "password", handle: "me", displayName: "Me")
        var iterator = backend.friends.makeAsyncIterator()
        let friends = await iterator.next() ?? []
        return (backend, friends)
    }

    func testSignUpSeedsDemoFriends() async throws {
        let (_, friends) = try await signedInBackend()
        XCTAssertEqual(Set(friends.map(\.handle)), ["alice", "bob"])
    }

    func testSendPokeSucceedsWhenFriendAllowsIt() async throws {
        let (backend, friends) = try await signedInBackend()
        let alice = try XCTUnwrap(friends.first(where: { $0.handle == "alice" }))
        // Seed data: alice.permissionsGrantedToMe.vibe allows up to intensity 60.
        try await backend.sendPoke(to: alice.id, stimulus: StimulusConfig(kind: .vibe, intensity: 40, repetitions: 1))
    }

    func testSendPokeThrowsWhenFriendHasNotAllowedIt() async throws {
        let (backend, friends) = try await signedInBackend()
        let bob = try XCTUnwrap(friends.first(where: { $0.handle == "bob" }))
        // Seed data: bob.permissionsGrantedToMe is .none — nothing allowed.
        do {
            try await backend.sendPoke(to: bob.id, stimulus: StimulusConfig(kind: .zap, intensity: 10, repetitions: 1))
            XCTFail("Expected sendPoke to throw when not allowed")
        } catch {
            // expected
        }
    }

    func testSendPokeThrowsWhenIntensityExceedsCap() async throws {
        let (backend, friends) = try await signedInBackend()
        let alice = try XCTUnwrap(friends.first(where: { $0.handle == "alice" }))
        // Seed data: alice allows zap up to intensity 30.
        do {
            try await backend.sendPoke(to: alice.id, stimulus: StimulusConfig(kind: .zap, intensity: 90, repetitions: 1))
            XCTFail("Expected sendPoke to throw when intensity exceeds the granted cap")
        } catch {
            // expected
        }
    }

    func testHandleIncomingPokeFiresOnConnectedDevice() async {
        let backend = MockSocialBackend(deviceRepository: FakeDeviceRepository())
        let payload = PokePushPayload(
            pokeID: UUID(), senderHandle: "alice", senderDisplayName: "Alice",
            stimulus: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)
        )
        let status = await backend.handleIncomingPoke(payload)
        XCTAssertEqual(status, .fired)
    }

    func testHandleIncomingPokeIsIdempotent() async {
        let backend = MockSocialBackend(deviceRepository: FakeDeviceRepository())
        let payload = PokePushPayload(
            pokeID: UUID(), senderHandle: "alice", senderDisplayName: "Alice",
            stimulus: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)
        )
        let first = await backend.handleIncomingPoke(payload)
        let second = await backend.handleIncomingPoke(payload)
        XCTAssertEqual(first, second)

        var iterator = backend.activity.makeAsyncIterator()
        let activity = await iterator.next() ?? []
        XCTAssertEqual(activity.filter { $0.id == payload.pokeID }.count, 1)
    }

    func testHandleIncomingPokeRespectsDoNotDisturb() async {
        UserDefaults.standard.set(true, forKey: PokeSettings.doNotDisturbKey)
        defer { UserDefaults.standard.removeObject(forKey: PokeSettings.doNotDisturbKey) }

        let backend = MockSocialBackend(deviceRepository: FakeDeviceRepository())
        let payload = PokePushPayload(
            pokeID: UUID(), senderHandle: "alice", senderDisplayName: "Alice",
            stimulus: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)
        )
        let status = await backend.handleIncomingPoke(payload)
        XCTAssertEqual(status, .muted)
    }
}

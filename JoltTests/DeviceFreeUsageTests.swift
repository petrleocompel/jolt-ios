import XCTest
@testable import Jolt

/// The wearable is optional. These pin the two halves of that: the social
/// features work with nothing connected, and `RootView`'s pairing offer keys
/// off "has a device ever been paired" rather than "is one connected right
/// now" — so losing the device mid-session can't eject you back to
/// onboarding.
@MainActor
final class DeviceFreeUsageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: PokeSettings.doNotDisturbKey)
    }

    private func signedInBackend(
        deviceRepository: DeviceRepository
    ) async throws -> (MockSocialBackend, [Friend]) {
        let backend = MockSocialBackend(deviceRepository: deviceRepository)
        try await backend.signUp(email: "me@example.com", password: "password", handle: "me", displayName: "Me")
        var iterator = backend.friends.makeAsyncIterator()
        let friends = await iterator.next() ?? []
        return (backend, friends)
    }

    // MARK: - Sending pokes without a device

    func testSendPokeSucceedsWithNoDevicePaired() async throws {
        let (backend, friends) = try await signedInBackend(
            deviceRepository: FakeDeviceRepository(startsPaired: false)
        )
        let alice = try XCTUnwrap(friends.first(where: { $0.handle == "alice" }))
        // Seed data: alice allows vibe up to 60. An outgoing poke is a server
        // call about *their* device — ours being absent is irrelevant.
        try await backend.sendPoke(to: alice.id, stimulus: StimulusConfig(kind: .vibe, intensity: 40, repetitions: 1))

        var iterator = backend.activity.makeAsyncIterator()
        let activity = await iterator.next() ?? []
        XCTAssertEqual(activity.first?.direction, .sent)
        XCTAssertEqual(activity.first?.status, .fired)
    }

    func testQuickPokeSucceedsWithNoDevicePaired() async throws {
        let (backend, friends) = try await signedInBackend(
            deviceRepository: FakeDeviceRepository(startsPaired: false)
        )
        let alice = try XCTUnwrap(friends.first(where: { $0.handle == "alice" }))
        let service = QuickPokeService(
            pokeRepository: backend,
            store: QuickPokeSettingsStore(defaults: isolatedDefaults())
        )
        service.setTarget(friendID: alice.id, name: alice.displayName)
        service.setStimulus(StimulusConfig(kind: .vibe, intensity: 40, repetitions: 1))

        service.sendQuickPoke()
        try await waitUntil { service.lastPokeSentAt != nil || service.lastError != nil }

        XCTAssertNil(service.lastError)
        XCTAssertNotNil(service.lastPokeSentAt)
    }

    /// The other direction: a poke arriving with no wearable around is
    /// recorded and acked as undeliverable rather than being lost or
    /// reported as a hit.
    func testIncomingPokeIsMarkedDeviceNotConnectedWithNoDevicePaired() async {
        let backend = MockSocialBackend(deviceRepository: FakeDeviceRepository(startsPaired: false))
        let status = await backend.handleIncomingPoke(PokePushPayload(
            pokeID: UUID(), senderHandle: "alice", senderDisplayName: "Alice",
            stimulus: StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)
        ))
        XCTAssertEqual(status, .deviceNotConnected)
    }

    // MARK: - The pairing offer is a first-run step, not a gate

    func testHasPairedDeviceIsFalseOnAFreshInstall() {
        let viewModel = DeviceControlViewModel(repository: FakeDeviceRepository(startsPaired: false))
        XCTAssertFalse(viewModel.hasPairedDevice)
        XCTAssertNil(viewModel.connectedDevice)
    }

    func testPairingIsRememberedAfterConnecting() async throws {
        let repository = FakeDeviceRepository(startsPaired: false)
        let viewModel = DeviceControlViewModel(repository: repository)

        viewModel.connect(to: PavlokDevice(peripheralIdentifier: UUID(), name: "pavlok-3", family: .pavlok3))
        try await waitUntil { viewModel.connectedDevice != nil }

        XCTAssertTrue(viewModel.hasPairedDevice)
    }

    /// Disconnecting — the device going out of range, Bluetooth off, or the
    /// Settings button — keeps the pairing, so `RootView` keeps showing the
    /// tabs instead of falling back to onboarding.
    func testDisconnectingKeepsThePairing() async throws {
        let repository = FakeDeviceRepository(startsPaired: true)
        let viewModel = DeviceControlViewModel(repository: repository)
        try await waitUntil { viewModel.connectedDevice != nil }

        viewModel.disconnect()
        try await waitUntil { viewModel.connectedDevice == nil }

        XCTAssertTrue(viewModel.hasPairedDevice)
    }

    func testForgettingClearsThePairing() async throws {
        let repository = FakeDeviceRepository(startsPaired: true)
        let viewModel = DeviceControlViewModel(repository: repository)
        try await waitUntil { viewModel.connectedDevice != nil }

        viewModel.forgetPairedDevice()
        try await waitUntil { !viewModel.hasPairedDevice }

        XCTAssertNil(viewModel.connectedDevice)
    }

    // MARK: - Helpers

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "DeviceFreeUsageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return defaults
    }

    /// These view models publish through detached `Task`s off an
    /// `AsyncStream`, so there's no completion to await — poll the observable
    /// result instead, with a ceiling so a genuine failure fails the test
    /// rather than hanging it.
    private func waitUntil(
        timeout: Duration = .seconds(3),
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition not met within \(timeout)", file: file, line: line)
    }
}

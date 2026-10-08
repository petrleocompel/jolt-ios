import XCTest
@testable import Jolt

@MainActor
final class FriendsViewModelTests: XCTestCase {
    private func signedInViewModel() async throws -> (FriendsViewModel, Friend) {
        let backend = MockSocialBackend(deviceRepository: FakeDeviceRepository())
        try await backend.signUp(email: "me@example.com", password: "password", handle: "me", displayName: "Me")
        let viewModel = FriendsViewModel(repository: backend)
        // Let the initial `friends` value (seeded at sign-up) reach the view model.
        try await Task.sleep(for: .milliseconds(20))
        let alice = try XCTUnwrap(viewModel.friends.first(where: { $0.handle == "alice" }))
        return (viewModel, alice)
    }

    /// `PermissionEditView`'s "Allow" toggle and its two steppers each read a
    /// `StimulusPermission` snapshot at render time and send a full
    /// overwrite of it. Flipping "Allow" on and then immediately bumping the
    /// intensity stepper — a natural sequence for a user to do — used to
    /// race: the second call could still be holding the pre-toggle snapshot
    /// if the first one's server round trip hadn't refreshed `friends` yet,
    /// silently reverting `isAllowed` back to false. `updatePermission`
    /// applies to `friends` immediately (not just after the network call)
    /// so this can't happen — this reproduces the exact interleaving.
    func testRapidPermissionEditsDontClobberEachOther() async throws {
        let (viewModel, alice) = try await signedInViewModel()

        // Seed data: alice's granted zap permission starts disabled.
        var permission = alice.permissionsIGranted[.zap]
        XCTAssertFalse(permission.isAllowed)

        permission.isAllowed = true
        viewModel.updatePermission(for: alice, kind: .zap, permission: permission)

        // Immediately afterwards — before the first update's network call
        // has any chance to complete — a second edit reads whatever
        // `updatePermission` left in `friends` right now.
        var second = try XCTUnwrap(viewModel.friends.first(where: { $0.id == alice.id })).permissionsIGranted[.zap]
        XCTAssertTrue(second.isAllowed, "the toggle should be visible locally before the network call returns")
        second.maxIntensity = 77
        viewModel.updatePermission(for: alice, kind: .zap, permission: second)

        let afterBothEdits = try XCTUnwrap(viewModel.friends.first(where: { $0.id == alice.id }))
        XCTAssertTrue(afterBothEdits.permissionsIGranted[.zap].isAllowed)
        XCTAssertEqual(afterBothEdits.permissionsIGranted[.zap].maxIntensity, 77)

        // Give both fire-and-forget network calls time to land, then confirm
        // the backend's own state agrees — not just the optimistic copy.
        try await Task.sleep(for: .milliseconds(50))
        let finalPermission = try XCTUnwrap(viewModel.friends.first(where: { $0.id == alice.id })).permissionsIGranted[.zap]
        XCTAssertTrue(finalPermission.isAllowed)
        XCTAssertEqual(finalPermission.maxIntensity, 77)
    }

    /// A preset (or any slider) carries no automation answer, and must not
    /// wipe the one already given — locally or in the backend.
    func testGrantEditsLeaveTheAutomationAnswerAlone() async throws {
        let (viewModel, alice) = try await signedInViewModel()

        // The mock takes 200 ms per write; let each one land.
        viewModel.updateAutomationConsent(for: alice, kind: .vibe, allowed: false)
        try await Task.sleep(for: .milliseconds(400))
        viewModel.updatePermission(for: alice, kind: .vibe, permission: .allowed(maxIntensity: 60, cooldownSeconds: 15))

        let optimistic = try XCTUnwrap(viewModel.friends.first(where: { $0.id == alice.id })).permissionsIGranted[.vibe]
        XCTAssertEqual(optimistic.maxIntensity, 60)
        XCTAssertEqual(optimistic.automationAllowed, false)
        XCTAssertEqual(optimistic.automationAllowedEffective, false)

        try await Task.sleep(for: .milliseconds(400))
        let saved = try XCTUnwrap(viewModel.friends.first(where: { $0.id == alice.id })).permissionsIGranted[.vibe]
        XCTAssertEqual(saved.maxIntensity, 60)
        XCTAssertEqual(saved.automationAllowed, false)
    }

    /// "Default" shows what the default means right away, from the server's
    /// policy, rather than whatever the old explicit answer was.
    func testResettingToDefaultShowsTheServerDefaultImmediately() async throws {
        let (viewModel, alice) = try await signedInViewModel()

        viewModel.updateAutomationConsent(for: alice, kind: .beep, allowed: false)
        viewModel.updateAutomationConsent(for: alice, kind: .beep, allowed: nil)

        let permission = try XCTUnwrap(viewModel.friends.first(where: { $0.id == alice.id })).permissionsIGranted[.beep]
        XCTAssertNil(permission.automationAllowed)
        XCTAssertEqual(permission.automationAllowedEffective, true, "the mock server allows automation by default")
    }

    func testAFailedConsentChangeRollsBackOnlyTheAnswer() async throws {
        var zap = StimulusPermission.allowed(maxIntensity: 30, cooldownSeconds: 60)
        zap.automationAllowedEffective = true
        let alice = Friend(
            id: UUID(), handle: "alice", displayName: "Alice",
            permissionsGrantedToMe: .none,
            permissionsIGranted: FriendPermissionSet(zap: zap, vibe: .disabled, beep: .disabled)
        )
        let viewModel = FriendsViewModel(repository: RejectingFriendsRepository(friends: [alice]))
        try await Task.sleep(for: .milliseconds(20))

        viewModel.updateAutomationConsent(for: alice, kind: .zap, allowed: false)
        let optimistic = try XCTUnwrap(viewModel.friends.first).permissionsIGranted[.zap]
        XCTAssertEqual(optimistic.automationAllowed, false)
        XCTAssertEqual(optimistic.automationAllowedEffective, false)

        try await Task.sleep(for: .milliseconds(50))
        let rolledBack = try XCTUnwrap(viewModel.friends.first).permissionsIGranted[.zap]
        XCTAssertEqual(rolledBack, zap)
        XCTAssertEqual(viewModel.lastError, "Rejected.")
    }
}

/// Refuses every write, so the view model's rollback can be watched.
@MainActor
private final class RejectingFriendsRepository: FriendsRepository {
    struct Rejected: LocalizedError {
        var errorDescription: String? { "Rejected." }
    }

    private let friendsHub = StreamHub<[Friend]>()

    init(friends: [Friend]) {
        friendsHub.yield(friends)
    }

    var friends: AsyncStream<[Friend]> { friendsHub.stream() }
    var incomingRequests: AsyncStream<[FriendRequest]> { AsyncStream { $0.finish() } }
    var outgoingRequests: AsyncStream<[FriendRequest]> { AsyncStream { $0.finish() } }
    let myHandle = "me"
    let myInviteCode = "JOLT-1"
    let serverPolicies: ServerPolicies? = ServerPolicies(automationConsentRequired: false)

    func sendRequest(handle: String) async throws { throw Rejected() }
    func sendRequest(inviteCode: String) async throws { throw Rejected() }
    func acceptRequest(_ id: FriendRequest.ID) async throws { throw Rejected() }
    func rejectRequest(_ id: FriendRequest.ID) async throws { throw Rejected() }
    func removeFriend(_ id: Friend.ID) async throws { throw Rejected() }
    func updatePermission(for friendID: Friend.ID, kind: StimulusKind, permission: StimulusPermission) async throws {
        throw Rejected()
    }
    func updateAutomationConsent(
        for friendID: Friend.ID, kind: StimulusKind, permission: StimulusPermission, allowed: Bool?
    ) async throws {
        throw Rejected()
    }
    func refreshFriends() async {}
}

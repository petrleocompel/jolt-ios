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
}

import Foundation

/// "Do notifications from the server actually reach this phone?" — everything
/// behind Settings → Notifications.
///
/// Separate from `PokeRepository` on purpose: a test push carries no poke, so
/// none of the friendship, permission or activity-log machinery applies to it.
/// What it shares with a poke is the delivery path, which is exactly what it
/// exists to exercise.
@MainActor
protocol PushDiagnosticsRepository {
    /// Every phone signed in to this account.
    func registeredDevices() async throws -> [RegisteredDevice]

    /// Asks the server to push to `deviceID`, or to all of them when nil.
    /// Pass a `stimulus` to have the phone fire it as well; omit it for a
    /// notification-only test that needs no wearable connected.
    func sendTestPush(to deviceID: UUID?, stimulus: StimulusConfig?) async throws -> TestPushStatus

    /// Re-reads a test's state, including acks that have landed since. Throws
    /// once the server has forgotten it (ten minutes).
    func testPushStatus(_ testID: UUID) async throws -> TestPushStatus

    /// The one "a test push arrived" entry point, called from every
    /// notification path. Fires the stimulus if the payload carries one, then
    /// tells the server what happened — that ack is what turns "Apple
    /// accepted it" into "the phone got it" on the sending screen.
    @discardableResult
    func handleIncomingTestPush(
        _ payload: TestPushPayload,
        path: TestPushPath
    ) async -> PokeDeliveryStatus?
}

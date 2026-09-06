import Foundation

/// Settings → Notifications, against a real server. Kept out of
/// `HTTPSocialBackend.swift` so neither file grows past readable size; the
/// endpoints are the `/devices*` group in the server contract.
extension HTTPSocialBackend: PushDiagnosticsRepository {
    private struct TestPushBody: Encodable {
        let deviceId: UUID?
        let stimulus: StimulusConfig?
    }

    private struct TestPushAckBody: Encodable {
        let deviceId: UUID
        let path: TestPushPath
        let status: PokeDeliveryStatus?
    }

    func registeredDevices() async throws -> [RegisteredDevice] {
        try await client.send("GET", "devices")
    }

    func sendTestPush(to deviceID: UUID?, stimulus: StimulusConfig?) async throws -> TestPushStatus {
        try await client.send(
            "POST", "devices/test-push",
            body: TestPushBody(deviceId: deviceID, stimulus: stimulus)
        )
    }

    func testPushStatus(_ testID: UUID) async throws -> TestPushStatus {
        try await client.send("GET", "devices/test-push/\(testID.uuidString)")
    }

    @discardableResult
    func handleIncomingTestPush(
        _ payload: TestPushPayload,
        path: TestPushPath
    ) async -> PokeDeliveryStatus? {
        // Only a test that asked for a stimulus touches the wearable. The
        // notification-only case still acks — arriving *is* the result.
        let status: PokeDeliveryStatus? = if let stimulus = payload.stimulus {
            await fireLocally(stimulus)
        } else {
            nil
        }

        // Best effort by design: a failed ack costs the sender their "delivered
        // in 1.2s" line, and nothing else. Never worth surfacing an error for,
        // least of all from a background push handler.
        try? await client.sendIgnoringResponse(
            "POST", "devices/test-push/\(payload.testID.uuidString)/ack",
            body: TestPushAckBody(deviceId: payload.deviceID, path: path, status: status)
        )
        return status
    }
}

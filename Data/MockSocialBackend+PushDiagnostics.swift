import Foundation

/// Settings → Notifications with no server behind it — snapshot runs and
/// previews. There is no APNs round trip to make, so the mock plays the part
/// the server and Apple would: it invents a device, fires anything the test
/// asked for, and hands back a status that already carries the ack.
///
/// `apnsConfigured` stays true: this is a demo of the screen working, not a
/// claim about a real server's credentials.
extension MockSocialBackend: PushDiagnosticsRepository {
    /// Stable across calls so the screen can mark it as "this device".
    private static let demoDeviceID = UUID(uuidString: "3FA85F64-5717-4562-B3FC-2C963F66AFA6") ?? UUID()

    func registeredDevices() async throws -> [RegisteredDevice] {
        [
            RegisteredDevice(
                id: Self.demoDeviceID,
                platform: "ios",
                tokenSuffix: "a1b2c3d4",
                isActive: true,
                createdAt: .now.addingTimeInterval(-86_400 * 12),
                lastSeenAt: .now
            )
        ]
    }

    func sendTestPush(to deviceID: UUID?, stimulus: StimulusConfig?) async throws -> TestPushStatus {
        try await Task.sleep(for: .milliseconds(400))
        let target = deviceID ?? Self.demoDeviceID
        let testID = UUID()
        let status = await handleIncomingTestPush(
            TestPushPayload(testID: testID, deviceID: target, stimulus: stimulus),
            path: .foreground
        )
        return TestPushStatus(
            testID: testID,
            sentAt: .now,
            stimulus: stimulus,
            apnsConfigured: true,
            devices: [TestPushDeviceResult(deviceID: target, isAccepted: true)],
            acks: [
                TestPushAck(
                    deviceID: target,
                    path: .foreground,
                    status: status,
                    receivedAt: .now,
                    elapsedMs: 420
                )
            ]
        )
    }

    /// Nothing to poll — `sendTestPush` already returned a settled status.
    func testPushStatus(_ testID: UUID) async throws -> TestPushStatus {
        throw MockTestPushExpired()
    }

    @discardableResult
    func handleIncomingTestPush(
        _ payload: TestPushPayload,
        path: TestPushPath
    ) async -> PokeDeliveryStatus? {
        guard let stimulus = payload.stimulus else { return nil }
        if UserDefaults.standard.bool(forKey: PokeSettings.doNotDisturbKey) {
            return .muted
        }
        do {
            try await deviceRepository.fire(stimulus)
            return .fired
        } catch {
            return .deviceNotConnected
        }
    }
}

/// The mock keeps no test history, so a status lookup always reads as one
/// the server has already forgotten.
private struct MockTestPushExpired: LocalizedError {
    var errorDescription: String? { "This test push has expired." }
}

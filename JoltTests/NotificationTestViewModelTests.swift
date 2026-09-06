import XCTest
@testable import Jolt

/// Records what was asked of the server and hands back whatever the test
/// wants, so the screen's logic can be exercised without a server or APNs.
@MainActor
private final class FakePushDiagnostics: PushDiagnosticsRepository {
    var devices: [RegisteredDevice] = []
    var statusToReturn: TestPushStatus?
    var sendError: Error?

    private(set) var sentTo: [UUID?] = []
    private(set) var sentStimuli: [StimulusConfig?] = []
    private(set) var acks: [(TestPushPayload, TestPushPath)] = []

    func registeredDevices() async throws -> [RegisteredDevice] { devices }

    func sendTestPush(to deviceID: UUID?, stimulus: StimulusConfig?) async throws -> TestPushStatus {
        sentTo.append(deviceID)
        sentStimuli.append(stimulus)
        if let sendError { throw sendError }
        return try XCTUnwrap(statusToReturn)
    }

    func testPushStatus(_ testID: UUID) async throws -> TestPushStatus {
        try XCTUnwrap(statusToReturn)
    }

    @discardableResult
    func handleIncomingTestPush(
        _ payload: TestPushPayload,
        path: TestPushPath
    ) async -> PokeDeliveryStatus? {
        acks.append((payload, path))
        return payload.stimulus == nil ? nil : .fired
    }
}

@MainActor
final class NotificationTestViewModelTests: XCTestCase {
    private let deviceID = UUID()

    private func device(tokenSuffix: String = "deadbeef") -> RegisteredDevice {
        RegisteredDevice(
            id: deviceID,
            platform: "ios",
            tokenSuffix: tokenSuffix,
            isActive: true,
            createdAt: .now,
            lastSeenAt: .now
        )
    }

    private func status(
        accepted: Bool = true,
        apnsConfigured: Bool = true,
        acks: [TestPushAck] = []
    ) -> TestPushStatus {
        TestPushStatus(
            testID: UUID(),
            sentAt: .now,
            stimulus: nil,
            apnsConfigured: apnsConfigured,
            devices: [
                TestPushDeviceResult(
                    deviceID: deviceID,
                    isAccepted: accepted,
                    reason: accepted ? nil : "unregistered",
                    detail: accepted ? nil : "BadDeviceToken"
                )
            ],
            acks: acks
        )
    }

    private func viewModel(_ repository: FakePushDiagnostics) -> NotificationTestViewModel {
        let model = NotificationTestViewModel(repository: repository)
        // The last 8 hex characters are what the server exposes.
        model.apnsToken = "0123456789abcdefdeadbeef"
        return model
    }

    func testMatchesThisDeviceByTokenSuffix() async {
        let repository = FakePushDiagnostics()
        repository.devices = [device(), RegisteredDevice(
            id: UUID(), platform: "ios", tokenSuffix: "11112222",
            isActive: true, createdAt: .now, lastSeenAt: .now
        )]
        let model = viewModel(repository)

        await model.refresh()

        XCTAssertEqual(model.thisDevice?.id, deviceID)
        XCTAssertTrue(model.isRegistered)
    }

    func testReportsUnregisteredWhenNoDeviceMatchesTheToken() async {
        let repository = FakePushDiagnostics()
        repository.devices = [RegisteredDevice(
            id: UUID(), platform: "ios", tokenSuffix: "11112222",
            isActive: true, createdAt: .now, lastSeenAt: .now
        )]
        let model = viewModel(repository)

        await model.refresh()

        XCTAssertNil(model.thisDevice)
        XCTAssertFalse(model.isRegistered)
    }

    func testSendsNotificationOnlyByDefault() async {
        let repository = FakePushDiagnostics()
        repository.devices = [device()]
        repository.statusToReturn = status()
        let model = viewModel(repository)
        await model.refresh()

        await model.send()

        // Targets this phone specifically, and leaves the wearable alone.
        XCTAssertEqual(repository.sentTo, [deviceID])
        XCTAssertEqual(repository.sentStimuli, [nil])
        model.cancelPolling()
    }

    func testSendsTheStimulusOnlyWhenAskedTo() async {
        let repository = FakePushDiagnostics()
        repository.devices = [device()]
        repository.statusToReturn = status()
        let model = viewModel(repository)
        await model.refresh()
        model.fireOnPavlok = true
        model.stimulus = StimulusConfig(kind: .zap, intensity: 45, repetitions: 2)

        await model.send()

        XCTAssertEqual(repository.sentStimuli.first ?? nil, StimulusConfig(kind: .zap, intensity: 45, repetitions: 2))
        model.cancelPolling()
    }

    func testFallsBackToEveryDeviceWhenThisOneIsUnknown() async {
        let repository = FakePushDiagnostics()
        repository.statusToReturn = status()
        let model = viewModel(repository)
        await model.refresh()

        await model.send()

        XCTAssertEqual(repository.sentTo, [nil])
        model.cancelPolling()
    }

    func testWaitsForConfirmationBeforeClaimingDelivery() async {
        let repository = FakePushDiagnostics()
        repository.devices = [device()]
        repository.statusToReturn = status()
        let model = viewModel(repository)
        await model.refresh()

        await model.send()

        // Apple accepting a push is not the phone receiving it.
        XCTAssertEqual(model.outcome, .waiting)
        model.cancelPolling()
    }

    func testReportsDeliveryOnceTheDeviceAcks() async {
        let ack = TestPushAck(
            deviceID: deviceID, path: .background, status: .fired, receivedAt: .now, elapsedMs: 1200
        )
        let repository = FakePushDiagnostics()
        repository.devices = [device()]
        repository.statusToReturn = status(acks: [ack])
        let model = viewModel(repository)
        await model.refresh()

        await model.send()

        XCTAssertEqual(model.outcome, .delivered(ack))
        model.cancelPolling()
    }

    func testReportsARejectedToken() async {
        let repository = FakePushDiagnostics()
        repository.devices = [device()]
        repository.statusToReturn = status(accepted: false)
        let model = viewModel(repository)
        await model.refresh()

        await model.send()

        XCTAssertEqual(model.outcome, .rejected(reason: "BadDeviceToken"))
        model.cancelPolling()
    }

    func testCallsOutAServerThatCannotPushAtAll() async {
        let repository = FakePushDiagnostics()
        repository.devices = [device()]
        repository.statusToReturn = status(apnsConfigured: false)
        let model = viewModel(repository)
        await model.refresh()

        await model.send()

        // Nothing will ever arrive, so "waiting" would be a lie.
        XCTAssertEqual(model.outcome, .notConfigured)
        model.cancelPolling()
    }

    func testSurfacesASendFailure() async {
        struct Failure: LocalizedError {
            var errorDescription: String? { "Too many test pushes — try again in 4s." }
        }
        let repository = FakePushDiagnostics()
        repository.devices = [device()]
        repository.sendError = Failure()
        let model = viewModel(repository)
        await model.refresh()

        await model.send()

        XCTAssertEqual(model.errorMessage, "Too many test pushes — try again in 4s.")
        XCTAssertNil(model.outcome)
    }
}

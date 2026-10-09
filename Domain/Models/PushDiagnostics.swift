import Foundation

/// One phone registered to the account, as `GET /devices` reports it. Only
/// the tail of the APNs token comes back from the server, which is enough for
/// this device to recognise itself in the list.
struct RegisteredDevice: Identifiable, Codable, Equatable {
    var id: UUID
    var platform: String
    var tokenSuffix: String
    /// False once APNs has told the server the token is dead.
    var isActive: Bool
    var createdAt: Date
    var lastSeenAt: Date
}

/// A device confirming a test push arrived, with how long it took.
struct TestPushAck: Codable, Equatable {
    var deviceID: UUID?
    var path: TestPushPath
    /// What happened when firing, for a test that carried a stimulus.
    var status: PokeDeliveryStatus?
    var receivedAt: Date
    var elapsedMs: Int

    enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case path, status, receivedAt, elapsedMs
    }
}

/// Per-device outcome as APNs reported it — "Apple accepted it", which is
/// not the same as "the phone got it". Only an ack proves the latter.
struct TestPushDeviceResult: Identifiable, Codable, Equatable {
    var deviceID: UUID
    /// Named for what it means rather than the contract's terse `ok`: Apple
    /// took the push, which is not yet proof anything received it.
    var isAccepted: Bool
    /// `unregistered`, `transient` or `rejected`. Present only on failure.
    var reason: String?
    /// APNs' own reason string, when it gave one.
    var detail: String?

    var id: UUID { deviceID }

    enum CodingKeys: String, CodingKey {
        case deviceID = "deviceId"
        case isAccepted = "ok"
        case reason, detail
    }
}

/// Live state of one test push. The server holds this in memory for ten
/// minutes and then forgets it, so a status that 404s is expected, not an
/// error worth showing.
struct TestPushStatus: Codable, Equatable {
    var testID: UUID
    var sentAt: Date
    var stimulus: StimulusConfig?
    /// False when the server has no way to push and is logging pushes
    /// instead of sending them — nothing will ever be acked. True through the
    /// relay as well; kept for servers that predate `pushTransport`.
    var apnsConfigured: Bool
    var devices: [TestPushDeviceResult]
    var acks: [TestPushAck]
    /// `apns`, `relay` or `none`: how the server sent it. Authoritative where
    /// present (C19); a server that predates the relay sends nothing.
    var pushTransport: String?

    /// Whether the server can deliver pushes at all.
    var canPush: Bool {
        pushTransport.map { $0 != "none" } ?? apnsConfigured
    }

    /// The first confirmation from `deviceID`, if any has arrived.
    func ack(for deviceID: UUID) -> TestPushAck? {
        acks.first { $0.deviceID == deviceID }
    }
}

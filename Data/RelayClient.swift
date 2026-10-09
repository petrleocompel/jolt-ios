import CryptoKit
import Foundation

/// The app's half of the push relay protocol (`jolt-relay/spec/protocol-v1.md`
/// section 4): register this phone's APNs token for one Jolt server, and
/// revoke that registration again.
///
/// Talks to the relay directly, never through the Jolt server: the server
/// must not see the APNs token, only the `relayToken` that stands in for it.
@MainActor
struct RelayClient {
    enum RelayError: LocalizedError, Equatable {
        /// The relay answered, and said no. `code` is its `error` field.
        case rejected(status: Int, code: String?)
        case transport(String)
        /// Answered with something that isn't the contract's JSON.
        case malformed

        var errorDescription: String? {
            switch self {
            case .rejected(_, "server_blocked"?): return "The relay has blocked this server."
            case .rejected(_, "unknown_server"?): return "The relay doesn't know this server yet."
            case .rejected(_, "attestation_failed"?): return "The relay couldn't verify this copy of the app."
            case .rejected(_, "app_not_allowed"?): return "The relay doesn't serve this build of the app."
            case .rejected(_, "registration_closed"?): return "The relay isn't taking new devices right now."
            case .rejected(_, "provider_unavailable"?): return "The relay can't reach Apple right now."
            case .rejected(let status, _): return "The relay answered \(status)."
            case .transport(let detail): return detail
            case .malformed: return "The relay sent an answer the app doesn't understand."
            }
        }
    }

    let baseURL: URL
    let session: URLSession
    let attestor: AppAttesting

    init(baseURL: URL, session: URLSession, attestor: AppAttesting) {
        self.baseURL = Self.normalizedBaseURL(baseURL)
        self.session = session
        self.attestor = attestor
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String
    }

    private struct RegisterBody: Encodable {
        let platform = "ios"
        let provider = "apns"
        let token: String
        let environment: String
        let appId: String
        let serverId: String
        let attestation: AttestationBody?
    }

    private struct AttestationBody: Encodable {
        let type = "apple-app-attest"
        let challenge: String
        let keyId: String
        let attestationObject: String?
        let assertion: String?
    }

    private struct RegisterResponse: Decodable {
        let relayToken: String
    }

    private struct UnregisterBody: Encodable {
        let relayToken: String
    }

    private struct ErrorBody: Decodable {
        let error: String
    }

    /// Registers `apnsToken` for the server with `serverId` and returns the
    /// relay's token for it. Registering the same pair again revokes the
    /// previous token.
    ///
    /// - Parameter environment: `production` or `sandbox`, whichever APNs
    ///   environment issued the token.
    func register(apnsToken: String, environment: String, appId: String, serverId: String) async throws -> String {
        let attestation = await attestation(apnsToken: apnsToken, serverId: serverId)
        let body = RegisterBody(
            token: apnsToken, environment: environment, appId: appId,
            serverId: serverId, attestation: attestation?.body
        )
        let response: RegisterResponse
        do {
            response = try await decode(perform("POST", "v1/devices", body: body))
        } catch RelayError.rejected(403, "attestation_failed"?) {
            // Only refused while the relay enforces attestation. A new key is
            // the one thing that might change its mind.
            attestor.reset()
            throw RelayError.rejected(status: 403, code: "attestation_failed")
        }
        if let evidence = attestation?.evidence {
            attestor.accepted(evidence)
        }
        return response.relayToken
    }

    /// Revokes a registration. The relay answers 204 for a token it doesn't
    /// know, so this only fails when the relay can't be reached. The token
    /// goes in the body, where access logs don't keep it (C5).
    func unregister(relayToken: String) async throws {
        _ = try await perform("POST", "v1/devices/unregister", body: UnregisterBody(relayToken: relayToken))
    }

    /// The relay's base URL may carry a path prefix and may or may not end in
    /// a slash (C1). Ending it in one makes `v1/…` resolve under the prefix,
    /// and makes two spellings of the same relay compare equal.
    nonisolated static func normalizedBaseURL(_ url: URL) -> URL {
        url.absoluteString.hasSuffix("/") ? url : URL(string: url.absoluteString + "/") ?? url
    }

    /// SHA-256 of `jolt-relay-v1|<challenge>|<token>|<serverId>`: what the
    /// App Attest evidence signs, binding it to this one registration.
    static func clientDataHash(challenge: String, apnsToken: String, serverId: String) -> Data {
        Data(SHA256.hash(data: Data("jolt-relay-v1|\(challenge)|\(apnsToken)|\(serverId)".utf8)))
    }

    /// Nil when there is nothing to attest with — the simulator, an older
    /// device — or when attesting failed. Either way the registration goes
    /// ahead without it: the relay logs a missing attestation rather than
    /// refusing it until it starts enforcing, and then it says so.
    private func attestation(
        apnsToken: String, serverId: String
    ) async -> (body: AttestationBody, evidence: AppAttestEvidence)? {
        guard attestor.isSupported else { return nil }
        do {
            let challenge: ChallengeResponse = try await decode(
                perform("GET", "v1/challenge", body: Optional<RegisterBody>.none)
            )
            let hash = Self.clientDataHash(challenge: challenge.challenge, apnsToken: apnsToken, serverId: serverId)
            let evidence = try await attestor.evidence(for: hash)
            let body = AttestationBody(
                challenge: challenge.challenge,
                keyId: evidence.keyId,
                attestationObject: evidence.attestationObject?.base64EncodedString(),
                assertion: evidence.assertion?.base64EncodedString()
            )
            return (body, evidence)
        } catch {
            print("[Jolt] registering with the relay without App Attest: \(error)")
            return nil
        }
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RelayError.malformed
        }
        return response
    }

    private func perform(_ method: String, _ path: String, body: (some Encodable)?) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RelayError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw RelayError.malformed }
        guard (200..<300).contains(http.statusCode) else {
            let code = try? JSONDecoder().decode(ErrorBody.self, from: data).error
            throw RelayError.rejected(status: http.statusCode, code: code)
        }
        return data
    }
}

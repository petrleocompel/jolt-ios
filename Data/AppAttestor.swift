import DeviceCheck
import Foundation

/// What a relay registration carries to prove it comes from a genuine build
/// of this app. Exactly one of `attestationObject` (first use of the key)
/// and `assertion` (every use after) is set.
struct AppAttestEvidence: Equatable {
    var keyId: String
    var attestationObject: Data?
    var assertion: Data?
}

/// App Attest, behind a protocol so tests (and the simulator, which has no
/// Secure Enclave to attest with) can stand in for it.
@MainActor
protocol AppAttesting {
    var isSupported: Bool { get }
    /// Evidence over `clientDataHash`, attesting a fresh key when there is no
    /// attested one yet.
    func evidence(for clientDataHash: Data) async throws -> AppAttestEvidence
    /// The relay accepted a registration made with this evidence. Only now is
    /// the key treated as attested, so a registration that never arrived
    /// attests again next time rather than asserting with a key the relay has
    /// never seen.
    func accepted(_ evidence: AppAttestEvidence)
    /// Forgets the key, so the next registration attests a new one.
    func reset()
}

/// `DCAppAttestService`, with the key id kept in `UserDefaults`. Not the
/// keychain: an App Attest key doesn't survive a reinstall, and neither
/// should the id that names it.
@MainActor
final class AppAttestor: AppAttesting {
    private let service = DCAppAttestService.shared
    private let defaults: UserDefaults
    private let keyIdKey = "cz.peelco.jolt.appAttest.keyId"
    private let attestedKey = "cz.peelco.jolt.appAttest.attested"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isSupported: Bool { service.isSupported }

    func evidence(for clientDataHash: Data) async throws -> AppAttestEvidence {
        if let keyId = defaults.string(forKey: keyIdKey), defaults.bool(forKey: attestedKey) {
            do {
                let assertion = try await service.generateAssertion(keyId, clientDataHash: clientDataHash)
                return AppAttestEvidence(keyId: keyId, assertion: assertion)
            } catch let error as DCError where error.code == .invalidKey {
                // Invalidated by the system (a restore onto another device,
                // most likely). Start over with a new key.
                reset()
            }
        }
        do {
            return try await attest(clientDataHash)
        } catch let error as DCError where error.code == .invalidKey {
            // A key that was attested already, for a registration that never
            // reached the relay, can't be attested twice.
            reset()
            return try await attest(clientDataHash)
        }
    }

    func accepted(_ evidence: AppAttestEvidence) {
        guard evidence.attestationObject != nil, defaults.string(forKey: keyIdKey) == evidence.keyId else { return }
        defaults.set(true, forKey: attestedKey)
    }

    func reset() {
        defaults.removeObject(forKey: keyIdKey)
        defaults.removeObject(forKey: attestedKey)
    }

    private func attest(_ clientDataHash: Data) async throws -> AppAttestEvidence {
        let keyId: String
        if let stored = defaults.string(forKey: keyIdKey) {
            keyId = stored
        } else {
            keyId = try await service.generateKey()
            defaults.set(keyId, forKey: keyIdKey)
            defaults.set(false, forKey: attestedKey)
        }
        let attestation = try await service.attestKey(keyId, clientDataHash: clientDataHash)
        return AppAttestEvidence(keyId: keyId, attestationObject: attestation)
    }
}

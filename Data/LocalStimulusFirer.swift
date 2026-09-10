import Foundation

/// The DND-gate → fire → status-mapping logic shared by both backends'
/// poke and test-push delivery paths. Extracted so `HTTPSocialBackend` and
/// `MockSocialBackend` can't reimplement (and silently diverge on) it —
/// which is exactly how the poke double-fire bug happened: the mock had an
/// idempotency guard the real backend didn't.
@MainActor
final class LocalStimulusFirer {
    private let deviceRepository: DeviceRepository
    private var handled: [UUID: PokeDeliveryStatus] = [:]

    init(deviceRepository: DeviceRepository) {
        self.deviceRepository = deviceRepository
    }

    /// Fires `stimulus` for `id` at most once. A second call with the same
    /// `id` (e.g. the same poke or test push arriving via both the silent
    /// background path and a notification tap) returns the first call's
    /// result instead of firing again. The reservation happens synchronously
    /// (no `await` between the check and the insert) so a second call
    /// racing in during the first call's `await` can't slip past the check
    /// too.
    @discardableResult
    func fire(id: UUID, stimulus: StimulusConfig) async -> PokeDeliveryStatus {
        if let existing = handled[id] { return existing }
        handled[id] = .pending
        let status: PokeDeliveryStatus
        if UserDefaults.standard.bool(forKey: PokeSettings.doNotDisturbKey) {
            status = .muted
        } else {
            do {
                try await deviceRepository.fire(stimulus)
                status = .fired
            } catch {
                status = .deviceNotConnected
            }
        }
        handled[id] = status
        return status
    }
}

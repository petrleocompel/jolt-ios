import Foundation

/// The DND-gate → fire → status-mapping logic shared by both backends'
/// poke and test-push delivery paths. Extracted so `HTTPSocialBackend` and
/// `MockSocialBackend` can't reimplement (and silently diverge on) it —
/// which is exactly how the poke double-fire bug happened: the mock had an
/// idempotency guard the real backend didn't.
@MainActor
final class LocalStimulusFirer {
    private let deviceRepository: DeviceRepository

    /// Pokes whose outcome is worth remembering: the stimulus reached the
    /// wearable, or the user's "do not disturb" setting deliberately
    /// swallowed it. Either way the poke is finished with — replaying it on
    /// the other delivery path would be a second shock the sender never
    /// sent.
    ///
    /// A *failed* attempt is deliberately absent from this map. See
    /// `fire(id:stimulus:)`.
    private var settled: [UUID: PokeDeliveryStatus] = [:]

    /// Attempts currently in flight, so two delivery paths landing on the
    /// same poke at the same moment share one BLE write instead of racing
    /// into two.
    private var inFlight: [UUID: Task<PokeDeliveryStatus, Never>] = [:]

    init(deviceRepository: DeviceRepository) {
        self.deviceRepository = deviceRepository
    }

    /// Fires `stimulus` for `id` at most once *successfully*.
    ///
    /// Every poke reaches the app twice by design — once as the silent
    /// background push, once as the alert the user sees or taps — so a
    /// second call with the same `id` must never shock twice.
    ///
    /// Only a delivered outcome (`.fired` or `.muted`) is remembered,
    /// though. The silent push routinely wakes the app before CoreBluetooth
    /// has restored the link, so its attempt fails with
    /// `.deviceNotConnected` through no fault of the wearable; caching that
    /// would poison the alert path arriving seconds later with the device
    /// connected, and the poke would never fire at all. A failed attempt is
    /// therefore forgotten, leaving the next delivery path free to retry
    /// it.
    ///
    /// The lookup and the reservation happen with no `await` between them,
    /// so a call racing in during another's BLE write joins that attempt
    /// rather than starting a second one.
    @discardableResult
    func fire(id: UUID, stimulus: StimulusConfig) async -> PokeDeliveryStatus {
        if let status = settled[id] { return status }
        if let attempt = inFlight[id] { return await attempt.value }

        let attempt = Task { @MainActor in
            let status = await self.deliver(stimulus)
            self.inFlight[id] = nil
            switch status {
            case .fired, .muted:
                self.settled[id] = status
            case .pending, .deviceNotConnected, .notAllowed:
                break
            }
            return status
        }
        // Reached before the task body can run: this actor is busy until the
        // `await` below, and the body needs the same executor.
        inFlight[id] = attempt
        return await attempt.value
    }

    private func deliver(_ stimulus: StimulusConfig) async -> PokeDeliveryStatus {
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

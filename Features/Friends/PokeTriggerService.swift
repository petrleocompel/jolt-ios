import Foundation
import Observation

/// Runs Approach A: while a wearable is connected and the trigger is enabled,
/// it watches the device's own notifications and, when the learned gesture
/// recurs, sends a friend poke through the normal poke path.
///
/// Also drives the "learn a gesture" capture in Settings — the same event feed
/// that arms the trigger is what the user records against.
///
/// Constructed once in `AppDependencies` and `start()`ed for the app's
/// lifetime; it self-manages subscription against the connection state, so it
/// costs nothing while no device is connected.
@MainActor
@Observable
final class PokeTriggerService {
    private let deviceRepository: DeviceRepository
    private let pokeRepository: PokeRepository
    private let store: PokeTriggerStore

    private(set) var trigger: PokeTrigger

    /// True while a device is connected — Settings uses it to explain why
    /// learning/arming is or isn't possible right now.
    private(set) var isDeviceConnected = false
    /// True while actively subscribed to the device's notifications.
    private(set) var isListening = false

    /// Capture-for-learning: when on, incoming events are recorded rather than
    /// matched, and the most recent one is offered as the gesture to learn.
    private(set) var isLearning = false
    private(set) var learnCandidate: DeviceEvent?

    /// Surfaced to Settings for a small activity line.
    private(set) var lastPokeSentAt: Date?
    private(set) var lastError: String?

    private var lastFiredAt: Date?

    @ObservationIgnored
    nonisolated(unsafe) private var connectionTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    init(
        deviceRepository: DeviceRepository,
        pokeRepository: PokeRepository,
        store: PokeTriggerStore = PokeTriggerStore()
    ) {
        self.deviceRepository = deviceRepository
        self.pokeRepository = pokeRepository
        self.store = store
        self.trigger = store.load()
    }

    deinit {
        connectionTask?.cancel()
        eventTask?.cancel()
    }

    /// Begins observing the connection state. Idempotent.
    func start() {
        guard connectionTask == nil else { return }
        connectionTask = Task { [weak self] in
            guard let self else { return }
            for await device in deviceRepository.connectedDevice {
                self.isDeviceConnected = device != nil
                self.reconcile()
            }
        }
    }

    // MARK: Settings-facing mutations

    func update(_ newTrigger: PokeTrigger) {
        trigger = newTrigger
        store.save(newTrigger)
        reconcile()
    }

    func setEnabled(_ enabled: Bool) {
        var updated = trigger
        updated.isEnabled = enabled
        update(updated)
    }

    func setTarget(friendID: Friend.ID, name: String) {
        var updated = trigger
        updated.targetFriendID = friendID
        updated.targetFriendName = name
        update(updated)
    }

    func setStimulus(_ stimulus: StimulusConfig) {
        var updated = trigger
        updated.stimulus = stimulus
        update(updated)
    }

    /// Begin recording. The next event the device sends becomes
    /// `learnCandidate`; `confirmLearn` then bakes it into the trigger.
    func startLearning() {
        learnCandidate = nil
        isLearning = true
        lastError = nil
        reconcile()
    }

    func cancelLearning() {
        isLearning = false
        learnCandidate = nil
        reconcile()
    }

    /// Save the captured gesture into the trigger.
    func confirmLearn(matchMode: PokeTrigger.MatchMode = .exact) {
        guard let candidate = learnCandidate else { return }
        var updated = trigger
        updated.learnedCharacteristicUUID = candidate.characteristicUUID
        updated.learnedBytes = candidate.data
        updated.matchMode = matchMode
        isLearning = false
        learnCandidate = nil
        update(updated)
    }

    func clearLearnedGesture() {
        var updated = trigger
        updated.learnedCharacteristicUUID = nil
        updated.learnedBytes = nil
        update(updated)
    }

    /// Switches how a *already-learned* gesture is matched, without
    /// recapturing it. Useful if `.exact` isn't firing reliably — some
    /// firmwares append a trailing counter/timestamp byte that makes two
    /// presses of the same physical gesture produce slightly different
    /// notifications; `.prefix` tolerates that. See `PokeTrigger.MatchMode`.
    func setMatchMode(_ mode: PokeTrigger.MatchMode) {
        var updated = trigger
        updated.matchMode = mode
        update(updated)
    }

    // MARK: Runtime

    /// Decides whether the event feed should be running, and (re)starts or
    /// stops it accordingly. Called whenever connection or configuration
    /// changes.
    private func reconcile() {
        let shouldListen = isDeviceConnected && (trigger.isEnabled || isLearning)
        if shouldListen {
            startEventLoop()
        } else {
            stopEventLoop()
        }
    }

    private func startEventLoop() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await deviceRepository.deviceEventStream()
                self.isListening = true
                for await event in stream {
                    self.handle(event)
                }
            } catch {
                self.lastError = error.localizedDescription
            }
            self.isListening = false
        }
    }

    private func stopEventLoop() {
        eventTask?.cancel()
        eventTask = nil
        isListening = false
    }

    private func handle(_ event: DeviceEvent) {
        if isLearning {
            learnCandidate = event
            return
        }
        guard trigger.isArmed, trigger.matches(event) else { return }
        if let last = lastFiredAt, Date().timeIntervalSince(last) < trigger.debounceSeconds {
            return
        }
        lastFiredAt = Date()
        fire()
    }

    private func fire() {
        guard let friendID = trigger.targetFriendID else { return }
        let stimulus = trigger.stimulus
        Task { [weak self] in
            guard let self else { return }
            do {
                try await pokeRepository.sendPoke(to: friendID, stimulus: stimulus)
                self.lastPokeSentAt = Date()
                self.lastError = nil
                BLELog.info("Poke trigger fired → poked \(self.trigger.targetFriendName ?? friendID.uuidString)")
            } catch {
                self.lastError = error.localizedDescription
                BLELog.error("Poke trigger failed to send: \(error.localizedDescription)")
            }
        }
    }
}

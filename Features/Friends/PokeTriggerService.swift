import Foundation
import Observation

/// Runs Approach A: while a wearable is connected and the trigger is enabled,
/// it watches the device's own notifications and, when the configured press
/// is announced, sends a friend poke through the normal poke path.
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
    /// Result of the last button-config write/read, shown in Settings.
    private(set) var lastButtonConfigNote: String?
    private(set) var isWritingButtonConfig = false

    /// The most recent notifications the device sent, newest first.
    ///
    /// The one question this feature always raises is "did the press even
    /// reach the phone?" — and until you can see the frames, a silent trigger
    /// and a silent device look identical. Capped at `recentEventLimit`.
    private(set) var recentEvents: [DeviceEvent] = []
    static let recentEventLimit = 12

    private var lastFiredAt: Date?
    /// Distinguishes "this loop finished" from "a newer loop replaced it", so
    /// a finishing task can clear `eventTask` without stomping its successor.
    private var eventLoopGeneration = 0
    /// Consecutive failures to open the event feed; resets on success. Bounds
    /// the retry so a permanently failing device can't spin.
    private var eventLoopFailures = 0
    private static let maxEventLoopRetries = 5

    @ObservationIgnored
    nonisolated(unsafe) private var connectionTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var eventTask: Task<Void, Never>?

    /// How long to wait before re-opening a failed event feed. Injectable so
    /// tests don't have to sit through the real delay.
    private let retryDelay: Duration

    init(
        deviceRepository: DeviceRepository,
        pokeRepository: PokeRepository,
        store: PokeTriggerStore = PokeTriggerStore(),
        retryDelay: Duration = .seconds(2)
    ) {
        self.deviceRepository = deviceRepository
        self.pokeRepository = pokeRepository
        self.store = store
        self.retryDelay = retryDelay
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

    func clearTarget() {
        var updated = trigger
        updated.targetFriendID = nil
        updated.targetFriendName = nil
        update(updated)
    }

    func setStimulus(_ stimulus: StimulusConfig) {
        var updated = trigger
        updated.stimulus = stimulus
        update(updated)
    }

    /// Choose which button sends the poke. Clears any learned signature,
    /// since the two are alternatives and leaving a stale blob behind only
    /// confuses the Settings screen.
    ///
    /// Choosing the button is not enough on its own — the device stays silent
    /// until `makeButtonReportPresses()` writes the action that makes it
    /// announce the press.
    func setButtonSlot(_ slot: DeviceButtonSlot?) {
        var updated = trigger
        updated.buttonSlot = slot
        if slot != nil {
            updated.learnedCharacteristicUUID = nil
            updated.learnedBytes = nil
        }
        update(updated)
    }

    /// Configures the chosen button so its press actually reaches the phone.
    ///
    /// This is the step the whole feature hangs on. A button set to a
    /// device-local action (zap, candle, timer) is handled inside the firmware
    /// and is never announced over BLE, so no amount of listening will see it.
    /// `findMyPhone` is the one phone-side action whose write payload is
    /// recovered; Jolt ignores the find-my-phone semantics and just takes the
    /// press. See `ButtonAction.isPhoneSideEffect`.
    ///
    /// The write is acknowledged (or refused) by the device: the setup
    /// characteristic requires write authorization, so a payload the firmware
    /// doesn't accept comes back as an ATT error rather than silently doing
    /// nothing. That makes the success note here mean something.
    func makeButtonReportPresses() async {
        guard let slot = trigger.buttonSlot else {
            lastButtonConfigNote = "Pick a button first."
            return
        }
        isWritingButtonConfig = true
        defer { isWritingButtonConfig = false }
        do {
            try await deviceRepository.setButtonConfig(ButtonConfig(slot: slot, action: .findMyPhone))
            lastButtonConfigNote = "\(slot.displayName) accepted by the device — press it to send a poke."
            lastError = nil
        } catch {
            lastButtonConfigNote = nil
            lastError = error.localizedDescription
        }
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
        updated.buttonSlot = nil
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
        eventLoopGeneration += 1
        let generation = eventLoopGeneration
        eventTask = Task { [weak self] in
            guard let self else { return }
            var failed = false
            do {
                let stream = try await deviceRepository.deviceEventStream()
                self.eventLoopFailures = 0
                self.isListening = true
                for await event in stream {
                    self.handle(event)
                }
            } catch {
                failed = true
                self.lastError = error.localizedDescription
                BLELog.error("Poke trigger event feed failed: \(error.localizedDescription)")
            }
            // Only a loop that is still the current one may clear the slot —
            // otherwise a task finishing right after `stopEventLoop()` started
            // a replacement would erase the new task's handle.
            guard self.eventLoopGeneration == generation else { return }
            self.isListening = false
            self.eventTask = nil
            // The feed also ends *without* an error when the peripheral drops.
            // Either way the loop has to be restartable: leaving `eventTask`
            // set (what this used to do) meant one hiccup deafened the trigger
            // until the app was relaunched, with nothing in the UI to say so.
            if failed {
                self.eventLoopFailures += 1
                guard self.eventLoopFailures <= Self.maxEventLoopRetries else {
                    BLELog.error("Poke trigger giving up after \(self.eventLoopFailures) failed attempts")
                    return
                }
                self.scheduleEventLoopRetry()
            } else {
                self.reconcile()
            }
        }
    }

    /// Re-opens the feed shortly after a failure. Delayed rather than
    /// immediate because the usual cause is a connect race — the connection
    /// stream says "connected" a moment before the repository can hand out a
    /// peripheral.
    private func scheduleEventLoopRetry() {
        let delay = retryDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.reconcile()
        }
    }

    private func stopEventLoop() {
        eventTask?.cancel()
        eventTask = nil
        eventLoopFailures = 0
        isListening = false
    }

    private func handle(_ event: DeviceEvent) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > Self.recentEventLimit {
            recentEvents.removeLast(recentEvents.count - Self.recentEventLimit)
        }
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

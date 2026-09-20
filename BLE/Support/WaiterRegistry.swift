import Foundation

/// Bookkeeping for a one-shot event that several callers can be waiting on
/// at the same time — "the services on this peripheral have been
/// discovered", "the characteristics in this service have been discovered".
///
/// It exists because the single-slot dictionaries it replaces silently
/// *dropped* a waiter. Two overlapping discoveries on one peripheral — the
/// connect-time device-info read and the poke trigger subscribing to
/// notifications, say — each stored their continuation under the
/// peripheral's identifier, so the second overwrote the first and the first
/// was never resumed: the task awaiting it hung for the rest of the session,
/// and its timeout resumed somebody else's continuation instead. That is how
/// a perfectly healthy device ended up with no battery reading on the
/// dashboard — `DeviceInformationReader` never got past discovery.
///
/// Generic over the waiter so the bookkeeping can be tested without
/// CoreBluetooth or continuations; see `WaiterRegistryTests`.
@MainActor
struct WaiterRegistry<Key: Hashable, Waiter> {
    /// Identifies one registration, so a timeout can withdraw *its own*
    /// waiter and leave everyone else still waiting.
    struct Token: Hashable {
        fileprivate let id = UUID()
        init() {}
    }

    private var waiters: [Key: [Token: Waiter]] = [:]

    var isEmpty: Bool { waiters.isEmpty }

    /// Registers `waiter` under `key`. The token is supplied by the caller
    /// so it can be captured by a timeout handler set up before the waiter
    /// itself exists.
    mutating func add(_ waiter: Waiter, token: Token, for key: Key) {
        waiters[key, default: [:]][token] = waiter
    }

    /// Withdraws one waiter. Returns `nil` when the event already happened
    /// and `takeAll` handed it out — which is exactly what a timeout firing
    /// just after the answer arrived should do: nothing.
    mutating func take(_ token: Token, for key: Key) -> Waiter? {
        let waiter = waiters[key]?.removeValue(forKey: token)
        if waiters[key]?.isEmpty == true { waiters.removeValue(forKey: key) }
        return waiter
    }

    /// Everyone waiting on `key` — the event happened, so they all get it.
    mutating func takeAll(for key: Key) -> [Waiter] {
        Array((waiters.removeValue(forKey: key) ?? [:]).values)
    }

    /// Every waiter whose key matches. Used when a peripheral disconnects:
    /// nothing parked on it can be answered now, and failing them is better
    /// than leaking the tasks.
    mutating func takeAll(where matches: (Key) -> Bool) -> [Waiter] {
        waiters.keys.filter(matches).flatMap { takeAll(for: $0) }
    }
}

import Foundation

/// One reorderable/hideable card on the Remote dashboard. The device-status
/// card is not one of these — it's pinned first, always shown, matching the
/// design doc ("Device status always stays pinned at the top").
enum RemoteWidgetKind: String, CaseIterable, Codable, Identifiable {
    case zap
    case vibe
    case beep
    case quickPoke
    case nextAlarm
    case recentActivity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zap: return StimulusKind.zap.displayName
        case .vibe: return StimulusKind.vibe.displayName
        case .beep: return StimulusKind.beep.displayName
        case .quickPoke: return "Quick poke"
        case .nextAlarm: return "Next alarm"
        case .recentActivity: return "Recent activity"
        }
    }

    var hint: String {
        switch self {
        case .zap: return "Hold to fire a shock at your saved intensity"
        case .vibe: return "Hold to fire a vibration at your saved intensity"
        case .beep: return "Hold to fire a beep at your saved intensity"
        case .quickPoke: return "One-tap poke to the friend you chose in Settings"
        case .nextAlarm: return "Time, stimulus and challenge for your next alarm"
        case .recentActivity: return "Pokes sent and received"
        }
    }

    var stimulusKind: StimulusKind? {
        switch self {
        case .zap: return .zap
        case .vibe: return .vibe
        case .beep: return .beep
        default: return nil
        }
    }
}

/// Which widgets are on the dashboard and in what order, plus which are
/// tucked away in the "gallery". Two separate lists rather than one ordered
/// list with a hidden set — reordering only ever happens within `visible`,
/// so keeping hidden widgets out of that array entirely avoids swapping a
/// visible widget past a hidden one that isn't actually on screen.
/// Persisted via `RemoteDashboardLayoutStore`.
struct RemoteDashboardLayout: Codable, Equatable {
    var visible: [RemoteWidgetKind]
    var hidden: [RemoteWidgetKind]

    static let `default` = RemoteDashboardLayout(
        visible: [.zap, .vibe, .beep, .quickPoke, .nextAlarm, .recentActivity],
        hidden: []
    )

    mutating func move(_ kind: RemoteWidgetKind, by offset: Int) {
        guard let index = visible.firstIndex(of: kind) else { return }
        let target = index + offset
        guard target >= 0, target < visible.count else { return }
        visible.swapAt(index, target)
    }

    mutating func hide(_ kind: RemoteWidgetKind) {
        guard let index = visible.firstIndex(of: kind) else { return }
        visible.remove(at: index)
        hidden.append(kind)
    }

    mutating func show(_ kind: RemoteWidgetKind) {
        guard let index = hidden.firstIndex(of: kind) else { return }
        hidden.remove(at: index)
        visible.append(kind)
    }

    /// Folds in any `RemoteWidgetKind` a future version might add that
    /// predates this saved layout, so it shows up in the gallery instead of
    /// silently never existing for this user.
    func reconciled() -> RemoteDashboardLayout {
        var copy = self
        let known = Set(visible).union(hidden)
        for kind in RemoteWidgetKind.allCases where !known.contains(kind) {
            copy.hidden.append(kind)
        }
        return copy
    }
}

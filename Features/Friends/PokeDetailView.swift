import SwiftUI

/// Everything the server knows about one poke.
///
/// The list it is pushed from is deliberately terse — who, what, roughly when
/// — so this is where the rest goes: the exact timestamps, how long the poke
/// took to be confirmed, what its status actually means, and the id to quote
/// when a poke turns up that nobody can explain (the server logs every
/// accepted poke under that id).
struct PokeDetailView: View {
    let event: PokeEvent

    var body: some View {
        List {
            Section { header }

            Section("Stimulus") {
                LabeledContent("Type", value: event.stimulus.kind.displayName)
                LabeledContent("Intensity", value: "\(event.stimulus.intensity)%")
                LabeledContent("Repetitions", value: "\(event.stimulus.repetitions)")
            }

            Section("Who") {
                LabeledContent(
                    event.direction == .sent ? "Recipient" : "Sender",
                    value: event.friendDisplayName
                )
                LabeledContent("Handle", value: "@\(event.friendHandle)")
                LabeledContent("Direction", value: event.direction == .sent ? "Sent" : "Received")
                if event.isAutomated {
                    LabeledContent("Sent by") {
                        Label(automationSource, systemImage: AutomatedPokeMark.symbolName)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Delivery") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        PokeStatusIcon(status: event.status)
                        Text(statusTitle)
                    }
                }
                Text(statusExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Sent", value: Self.exact(event.createdAt))
                if let ackedAt = event.ackedAt {
                    LabeledContent("Confirmed", value: Self.exact(ackedAt))
                    if let elapsed = event.timeToAck {
                        LabeledContent("Took", value: Self.duration(elapsed))
                    }
                }
            }

            Section("Reference") {
                LabeledContent("Poke ID") {
                    Text(event.id.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Poke")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pokeDetail")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: event.stimulus.kind.symbolName)
                .font(.title2)
                .foregroundStyle(RemoteTheme.violetInk)
                .frame(width: 46, height: 46)
                .background(RemoteTheme.violet.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                HStack(spacing: 4) {
                    if event.isAutomated { AutomatedPokeMark() }
                    Text(RelativeTime.string(for: event.createdAt))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Which script, when it's ours to know: the server only names the
    /// token to its owner, and not at all once it has been revoked.
    private var automationSource: String {
        switch event.direction {
        case .sent:
            return event.apiTokenName.map { "Script \u{201C}\($0)\u{201D}" } ?? "Your script"
        case .received:
            return "\(event.friendDisplayName)'s script"
        }
    }

    private var title: String {
        switch event.direction {
        case .sent:
            return "You \(event.stimulus.kind.pastTenseVerb) \(event.friendDisplayName)"
        case .received:
            return "\(event.friendDisplayName) \(event.stimulus.kind.pastTenseVerb) you"
        }
    }

    private var statusTitle: String {
        switch event.status {
        case .pending: return "Pending"
        case .fired: return "Fired"
        case .deviceNotConnected: return "Device not connected"
        case .notAllowed: return "Not allowed"
        case .muted: return "Muted"
        }
    }

    /// Plain English, because the raw value is the one thing on this screen a
    /// reader has no way to interpret on their own.
    private var statusExplanation: String {
        let them = event.direction == .sent ? event.friendDisplayName : "You"
        switch event.status {
        case .pending:
            return "Accepted and pushed, but no device has reported back yet. "
                + "iOS gives no delivery guarantee for the silent push, so a poke can stay pending."
        case .fired:
            return "Reached the Pavlok and actuated it."
        case .deviceNotConnected:
            return "The push arrived, but \(them.lowercased() == "you" ? "your" : "\(them)'s") "
                + "Pavlok wasn't connected to fire it on."
        case .notAllowed:
            return "The receiving side refused it — the permission re-check rejected this stimulus."
        case .muted:
            return "\(them) had \"Do not disturb\" for pokes switched on."
        }
    }

    private static func exact(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private static func duration(_ elapsed: TimeInterval) -> String {
        elapsed < 1
            ? String(format: "%.0f ms", elapsed * 1000)
            : String(format: "%.1f s", elapsed)
    }
}

/// Marks a poke a script sent (through an API token) rather than a person.
/// Shared by every list that shows pokes, so it reads the same everywhere.
struct AutomatedPokeMark: View {
    static let symbolName = "gearshape.2"

    var body: some View {
        Image(systemName: Self.symbolName)
            .accessibilityLabel("Sent by a script")
    }
}

/// Shared by the activity list and the detail screen so one poke can't be
/// green in one place and orange in the other.
struct PokeStatusIcon: View {
    let status: PokeDeliveryStatus

    var body: some View {
        switch status {
        case .pending:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .fired:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .deviceNotConnected:
            Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(.orange)
        case .notAllowed:
            Image(systemName: "hand.raised.fill").foregroundStyle(.red)
        case .muted:
            Image(systemName: "bell.slash.fill").foregroundStyle(.secondary)
        }
    }
}

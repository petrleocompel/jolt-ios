import SwiftUI

// MARK: - Next alarm card

struct NextAlarmCard: View {
    let alarm: Alarm
    let occursAt: Date
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NEXT ALARM")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.45))
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(timeString).font(.remoteNumeral(32)).foregroundStyle(.white)
                    Text(relativeString).font(.footnote).foregroundStyle(.white.opacity(0.45))
                }
                Text(summary).font(.footnote).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .remoteCard(.neutral)
    }

    private var timeString: String { String(format: "%02d:%02d", alarm.hour, alarm.minute) }

    private var relativeString: String {
        let interval = max(0, occursAt.timeIntervalSinceNow)
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        return "in \(hours)h \(minutes)m"
    }

    private var summary: String {
        var text = "\(alarm.stimulus.kind.displayName) \(alarm.stimulus.intensity)%"
        if alarm.dismissChallenge != .none {
            text += " · \(alarm.dismissChallenge.displayName)"
        }
        return text
    }
}

// MARK: - Recent activity card

struct RecentActivityCard: View {
    let events: [PokeEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RECENT ACTIVITY")
                .font(.caption2.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.45))
            ForEach(events) { event in
                HStack(spacing: 11) {
                    Text(title(for: event))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer(minLength: 8)
                    // A fixed string, not `style: .relative`: two rows of
                    // counters ticking out of step read as activity on a
                    // dashboard that is otherwise still.
                    Text(RelativeTime.string(for: event.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.38))
                }
            }
        }
        .remoteCard(.neutral)
    }

    private func title(for event: PokeEvent) -> String {
        switch event.direction {
        case .sent: return "You \(event.stimulus.kind.pastTenseVerb) \(event.friendDisplayName)"
        case .received: return "\(event.friendDisplayName) \(event.stimulus.kind.pastTenseVerb) you"
        }
    }
}

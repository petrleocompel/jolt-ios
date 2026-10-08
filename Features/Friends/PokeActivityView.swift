import SwiftUI

struct PokeActivityView: View {
    let pokeViewModel: PokeViewModel

    var body: some View {
        List(pokeViewModel.activity) { event in
            NavigationLink {
                PokeDetailView(event: event)
            } label: {
                row(for: event)
            }
        }
        .accessibilityIdentifier("pokeActivityList")
        .navigationTitle("Activity")
        .overlay {
            if pokeViewModel.activity.isEmpty {
                ContentUnavailableView("No pokes yet", systemImage: "hand.tap")
            }
        }
    }

    private func row(for event: PokeEvent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: event)).font(.subheadline)
                // Deliberately not `Text(_:style: .relative)`: that ticks once
                // a second, so a screenful of pokes becomes a screenful of
                // counters. The exact time is one tap away in the detail.
                HStack(spacing: 4) {
                    if event.isAutomated { AutomatedPokeMark() }
                    Text(
                        "\(RelativeTime.string(for: event.createdAt)) · "
                            + "\(event.stimulus.kind.displayName) \(event.stimulus.intensity)%"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            PokeStatusIcon(status: event.status)
        }
        .accessibilityIdentifier("pokeActivityRow")
    }

    private func title(for event: PokeEvent) -> String {
        switch event.direction {
        case .sent:
            return "You \(event.stimulus.kind.pastTenseVerb) \(event.friendDisplayName)"
        case .received:
            return "\(event.friendDisplayName) \(event.stimulus.kind.pastTenseVerb) you"
        }
    }
}

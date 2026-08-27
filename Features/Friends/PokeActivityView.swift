import SwiftUI

struct PokeActivityView: View {
    let pokeViewModel: PokeViewModel

    var body: some View {
        List(pokeViewModel.activity) { event in
            HStack {
                VStack(alignment: .leading) {
                    Text(title(for: event)).font(.subheadline)
                    Text(event.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusIcon(for: event.status)
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

    private func title(for event: PokeEvent) -> String {
        switch event.direction {
        case .sent:
            return "You \(event.stimulus.kind.pastTenseVerb) \(event.friendDisplayName)"
        case .received:
            return "\(event.friendDisplayName) \(event.stimulus.kind.pastTenseVerb) you"
        }
    }

    @ViewBuilder
    private func statusIcon(for status: PokeDeliveryStatus) -> some View {
        switch status {
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

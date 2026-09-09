import SwiftUI

/// Choose a stimulus, dial intensity within the recipient's permission cap,
/// set repetitions, then fire. Embedded inline on `FriendDetailView` (same
/// screen depth as before — nothing pushes to a new view) and, pre-loaded
/// with the Settings → Quick Poke friend, presented as a one-off override
/// sheet from the Remote dashboard's quick-poke card.
///
/// Uses adaptive system colors rather than the Remote dashboard's forced-
/// black palette: unlike the dashboard/customize/device-detail screens, this
/// lives inside ordinary system-chrome screens (a grouped `List` here, a
/// plain sheet from Remote) and needs to read correctly in light mode too.
struct PokeComposerCard: View {
    let friend: Friend
    let pokeViewModel: PokeViewModel
    let firingMode: FiringInteractionMode

    @State private var selectedKind: StimulusKind?
    @State private var intensity: Double = 20
    @State private var repetitions = 1

    private var allowedKinds: [StimulusKind] { friend.permissionsGrantedToMe.allowedKinds }

    var body: some View {
        Group {
            if allowedKinds.isEmpty {
                Text("\(friend.displayName) hasn't allowed you to poke them yet.")
                    .foregroundStyle(.secondary)
            } else {
                composer
            }
        }
        .onChange(of: selectedKind) { _, newKind in
            guard let newKind else { return }
            clampIntensity(to: newKind)
        }
    }

    @ViewBuilder
    private var composer: some View {
        let kind = selectedKind ?? allowedKinds[0]
        let cap = friend.permissionsGrantedToMe[kind].maxIntensity

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ForEach(allowedKinds) { candidate in
                    stimulusChip(candidate, isOn: candidate == kind)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("INTENSITY")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(Int(intensity))").font(.remoteNumeral(30))
                        Text("%").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Slider(value: $intensity, in: 0...Double(max(cap, 1)))
                    .tint(RemoteTheme.violet)
                    .accessibilityIdentifier("pokeIntensitySlider")
                Text("\(friend.displayName)'s cap: \(cap)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Repetitions: \(repetitions)")
                Spacer()
                Stepper("", value: $repetitions, in: 1...5)
                    .labelsHidden()
            }

            FireControl(
                mode: firingMode,
                confirmTitle: "Poke \(friend.displayName)?",
                confirmMessage: "\(kind.displayName) at \(Int(intensity))%.",
                onFire: {
                    let stimulus = StimulusConfig(kind: kind, intensity: Int(intensity), repetitions: repetitions)
                    pokeViewModel.send(to: friend, stimulus: stimulus)
                },
                label: { state in
                    HoldFillBar(
                        isHolding: state.isHolding,
                        progress: state.progress,
                        idleLabel: "\(firingMode.actionVerb) to poke \(friend.displayName)",
                        holdingLabel: "Keep holding…",
                        tint: RemoteTheme.violet,
                        ink: .white
                    )
                }
            )
            .accessibilityIdentifier("sendPokeButton")

            if let error = pokeViewModel.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func stimulusChip(_ kind: StimulusKind, isOn: Bool) -> some View {
        Button {
            selectedKind = kind
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.symbolName)
                Text(kind.displayName).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? RemoteTheme.violetInk : Color.secondary)
        .background(isOn ? RemoteTheme.violet.opacity(0.16) : Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isOn ? RemoteTheme.violet.opacity(0.6) : .clear)
        )
    }

    private func clampIntensity(to kind: StimulusKind) {
        intensity = min(intensity, Double(friend.permissionsGrantedToMe[kind].maxIntensity))
    }
}

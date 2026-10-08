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
    let firingModeService: FiringModeService
    let draftStore: FriendPokeDraftStore
    let feedback: PokeFeedbackService

    @State private var selectedKind: StimulusKind?
    @State private var intensity: Double = Double(FriendPokeDraft.preferredDefault.intensity)
    @State private var repetitions = 1
    @State private var didLoadDraft = false

    private var allowedKinds: [StimulusKind] { friend.permissionsGrantedToMe.allowedKinds }

    private var activeKind: StimulusKind? {
        if let selectedKind { return selectedKind }
        return allowedKinds.first
    }

    private var firingMode: FiringInteractionMode {
        guard let kind = activeKind else { return .tap }
        return firingModeService.mode(for: kind)
    }

    var body: some View {
        Group {
            if allowedKinds.isEmpty {
                Text("\(friend.displayName) hasn't allowed you to poke them yet.")
                    .foregroundStyle(.secondary)
            } else {
                composer
            }
        }
        .onAppear { loadDraftIfNeeded() }
        .onChange(of: friend.id) { _, _ in
            didLoadDraft = false
            loadDraftIfNeeded()
        }
        .onChange(of: selectedKind) { _, newKind in
            guard let newKind else { return }
            clampIntensity(to: newKind)
            persistDraft()
        }
        .onChange(of: intensity) { _, _ in
            persistDraft()
        }
    }

    @ViewBuilder
    private var composer: some View {
        let kind = activeKind ?? allowedKinds[0]
        let cap = friend.permissionsGrantedToMe[kind].maxIntensity
        let mode = firingMode

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
                // Pokes from here are in person and unaffected; this is for
                // whoever also pokes from scripts and wonders why one failed.
                if friend.permissionsGrantedToMe[kind].automationAllowedEffective == false {
                    Label("Your scripts can't send \(friend.displayName) \(kind.displayName.lowercased())s", systemImage: "gearshape.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("pokeAutomationBlockedNote")
                }
            }

            HStack {
                Text("Repetitions: \(repetitions)")
                Spacer()
                Stepper("", value: $repetitions, in: 1...5)
                    .labelsHidden()
            }

            if pokeViewModel.isSending {
                sendingBar
            } else if let error = pokeViewModel.lastError {
                errorCard(error)
            } else {
                FireControl(
                    mode: mode,
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
                            idleLabel: "\(mode.actionVerb) to poke \(friend.displayName)",
                            holdingLabel: "Keep holding…",
                            tint: RemoteTheme.violet,
                            ink: .white,
                            isShowingSuccess: feedback.isShowingSuccessLabel,
                            isFlashing: feedback.isFlashing
                        )
                    }
                )
                .accessibilityIdentifier("sendPokeButton")
            }
        }
    }

    private var eyebrow: String {
        switch pokeViewModel.lastFailure {
        case .unconfirmed: return "NOT CONFIRMED"
        case .notSent: return "COULDN'T REACH THE SERVER"
        case .refused, nil: return "POKE NOT SENT"
        }
    }

    private var sendingBar: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.white)
            Text("Sending…").font(.remoteNumeral(16))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(RemoteTheme.violet.opacity(0.35), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pokeSendingIndicator")
    }

    /// Replaces the send button rather than sitting under it: until the
    /// failure is acknowledged, "send again" should be a deliberate Retry.
    ///
    /// Retry is offered for every kind of failure, including the one where the
    /// poke may already have landed: it resends under the same poke id, so
    /// the server answers a poke it already has instead of sending another.
    private func errorCard(_ message: String) -> some View {
        StatusCard(
            tint: pokeViewModel.lastFailure == .unconfirmed ? .orange : .red,
            eyebrow: eyebrow,
            message: message
        ) {
            HStack(spacing: 10) {
                StatusCardButton(title: "Retry", fill: RemoteTheme.violet, ink: .white) {
                    pokeViewModel.retryLastSend()
                }
                StatusCardButton(title: "Dismiss") { pokeViewModel.dismissError() }
            }
        }
        .accessibilityIdentifier("pokeErrorCard")
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

    private func loadDraftIfNeeded() {
        guard !didLoadDraft else { return }
        didLoadDraft = true
        guard let draft = FriendPokeDraft.resolved(
            saved: draftStore.load(friendID: friend.id),
            permissions: friend.permissionsGrantedToMe
        ) else { return }
        selectedKind = draft.kind
        intensity = Double(draft.intensity)
    }

    private func persistDraft() {
        guard didLoadDraft, let kind = selectedKind ?? activeKind else { return }
        draftStore.save(
            FriendPokeDraft(kind: kind, intensity: Int(intensity)),
            for: friend.id
        )
    }

    private func clampIntensity(to kind: StimulusKind) {
        intensity = min(intensity, Double(friend.permissionsGrantedToMe[kind].maxIntensity))
    }
}

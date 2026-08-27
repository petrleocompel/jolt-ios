import SwiftUI

struct FriendDetailView: View {
    let friendID: Friend.ID
    let friendsViewModel: FriendsViewModel
    let pokeViewModel: PokeViewModel

    @State private var selectedKind: StimulusKind?
    @State private var intensity: Double = 20
    @State private var repetitions = 1

    /// Looked up fresh from the view model each render (rather than taking
    /// a `Friend` value passed in at navigation time) so permission edits
    /// made on the pushed `PermissionEditView` reflect back here live.
    private var friend: Friend? {
        friendsViewModel.friends.first(where: { $0.id == friendID })
    }

    var body: some View {
        Group {
            if let friend {
                content(for: friend)
            } else {
                ContentUnavailableView("Friend not found", systemImage: "person.slash")
            }
        }
    }

    @ViewBuilder
    private func content(for friend: Friend) -> some View {
        List {
            Section("Poke") {
                PokeComposerSection(
                    friend: friend,
                    pokeViewModel: pokeViewModel,
                    selectedKind: $selectedKind,
                    intensity: $intensity,
                    repetitions: $repetitions
                )
            }

            Section {
                NavigationLink("Permissions you've granted \(friend.displayName)") {
                    PermissionEditView(friendID: friend.id, viewModel: friendsViewModel)
                }
                #if DEBUG
                Button("Simulate incoming poke from \(friend.displayName)") {
                    let stimulus = StimulusConfig(kind: .zap, intensity: 20, repetitions: 1)
                    pokeViewModel.simulateIncoming(from: friend, stimulus: stimulus)
                }
                .accessibilityIdentifier("simulateIncomingPokeButton")
                #endif
                Button("Remove friend", role: .destructive) {
                    friendsViewModel.remove(friend)
                }
            }

            if let error = pokeViewModel.lastError {
                Section {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(friend.displayName)
    }
}

private struct PokeComposerSection: View {
    let friend: Friend
    let pokeViewModel: PokeViewModel
    @Binding var selectedKind: StimulusKind?
    @Binding var intensity: Double
    @Binding var repetitions: Int

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

        Picker("Stimulus", selection: Binding(get: { kind }, set: { selectedKind = $0 })) {
            ForEach(allowedKinds) { kind in
                Text(kind.displayName).tag(kind)
            }
        }
        Slider(value: $intensity, in: 0...Double(max(cap, 1)))
            .accessibilityIdentifier("pokeIntensitySlider")
        Text("Intensity: \(Int(intensity)) (max \(cap))")
            .font(.caption)
            .foregroundStyle(.secondary)
        Stepper("Repetitions: \(repetitions)", value: $repetitions, in: 1...5)
        Button("Poke \(friend.displayName)") {
            let stimulus = StimulusConfig(kind: kind, intensity: Int(intensity), repetitions: repetitions)
            pokeViewModel.send(to: friend, stimulus: stimulus)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("sendPokeButton")
    }

    private func clampIntensity(to kind: StimulusKind) {
        intensity = min(intensity, Double(friend.permissionsGrantedToMe[kind].maxIntensity))
    }
}

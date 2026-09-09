import SwiftUI

struct FriendDetailView: View {
    let friendID: Friend.ID
    let friendsViewModel: FriendsViewModel
    let pokeViewModel: PokeViewModel
    @Environment(AppDependencies.self) private var dependencies

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
                PokeComposerCard(
                    friend: friend,
                    pokeViewModel: pokeViewModel,
                    firingMode: dependencies.firingModeService.mode
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
        }
        .navigationTitle(friend.displayName)
    }
}

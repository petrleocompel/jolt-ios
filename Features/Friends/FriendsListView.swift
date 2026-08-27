import SwiftUI

struct FriendsListView: View {
    let authViewModel: AuthViewModel
    @Environment(AppDependencies.self) private var dependencies
    @State private var friendsViewModel: FriendsViewModel?
    @State private var pokeViewModel: PokeViewModel?
    @State private var isAddingFriend = false

    var body: some View {
        NavigationStack {
            Group {
                if let friendsViewModel, let pokeViewModel {
                    List {
                        if !friendsViewModel.incomingRequests.isEmpty {
                            Section("Requests") {
                                ForEach(friendsViewModel.incomingRequests) { request in
                                    IncomingRequestRow(request: request, viewModel: friendsViewModel)
                                }
                            }
                        }

                        Section("Friends") {
                            if friendsViewModel.friends.isEmpty {
                                Text("No friends yet — add one to send or receive pokes.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(friendsViewModel.friends) { friend in
                                NavigationLink {
                                    FriendDetailView(friendID: friend.id, friendsViewModel: friendsViewModel, pokeViewModel: pokeViewModel)
                                } label: {
                                    FriendRow(friend: friend)
                                }
                            }
                        }

                        if !friendsViewModel.outgoingRequests.isEmpty {
                            Section("Pending") {
                                ForEach(friendsViewModel.outgoingRequests) { request in
                                    HStack {
                                        Text("@\(request.handle)")
                                        Spacer()
                                        Text("Pending").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        Section {
                            NavigationLink("Poke activity") {
                                PokeActivityView(pokeViewModel: pokeViewModel)
                            }
                        }
                    }
                    .accessibilityIdentifier("friendsList")
                    .navigationTitle("Friends")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                isAddingFriend = true
                            } label: {
                                Image(systemName: "person.badge.plus")
                            }
                            .accessibilityIdentifier("addFriendButton")
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            Menu {
                                Text("@\(friendsViewModel.myHandle)")
                                Button("Log out", role: .destructive) { authViewModel.logOut() }
                            } label: {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                    }
                    .sheet(isPresented: $isAddingFriend) {
                        AddFriendView(viewModel: friendsViewModel)
                    }
                } else {
                    ProgressView()
                }
            }
            .task {
                if friendsViewModel == nil {
                    friendsViewModel = FriendsViewModel(repository: dependencies.friendsRepository)
                }
                if pokeViewModel == nil {
                    pokeViewModel = PokeViewModel(repository: dependencies.pokeRepository)
                }
            }
        }
    }
}

private struct IncomingRequestRow: View {
    let request: FriendRequest
    let viewModel: FriendsViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(request.displayName).font(.headline)
                Text("@\(request.handle)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Accept") { viewModel.accept(request) }
                .buttonStyle(.borderedProminent)
            Button("Ignore") { viewModel.reject(request) }
                .buttonStyle(.bordered)
        }
    }
}

private struct FriendRow: View {
    let friend: Friend

    var body: some View {
        VStack(alignment: .leading) {
            Text(friend.displayName).font(.headline)
            Text("@\(friend.handle) · can send: \(allowedSummary)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var allowedSummary: String {
        let kinds = friend.permissionsGrantedToMe.allowedKinds
        return kinds.isEmpty ? "nothing" : kinds.map(\.displayName).joined(separator: ", ")
    }
}

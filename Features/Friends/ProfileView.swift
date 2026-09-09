import SwiftUI

/// "My profile" — reached from the Friends tab's toolbar. Shows who you are
/// (name, handle), a couple of at-a-glance social stats, and the same
/// invite QR/handle already used in `AddFriendView` so someone can add you
/// without you needing to find that sheet. Pavlok linking itself stays a
/// Settings concern — this only shows whether one is linked, as an identity
/// fact, not a place to sign in or out of it.
struct ProfileView: View {
    let authViewModel: AuthViewModel
    let friendsViewModel: FriendsViewModel

    /// Read-only summary; sign-in/out for the Pavlok account stays in
    /// Settings → Pavlok account. Synchronous `init` already loads any saved
    /// account from the keychain, so no `.task { restore() }` is needed here.
    @State private var pavlokViewModel = PavlokAccountViewModel()

    private var displayName: String {
        authViewModel.currentUser?.displayName ?? "@\(friendsViewModel.myHandle)"
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 84, height: 84)
                        .overlay(
                            Text(initials)
                                .font(.title.bold())
                                .foregroundStyle(Color.accentColor)
                        )
                    VStack(spacing: 2) {
                        Text(displayName).font(.title3.bold())
                        Text("@\(friendsViewModel.myHandle)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            Section {
                LabeledContent {
                    Text("\(friendsViewModel.friends.count)")
                } label: {
                    Label("Friends", systemImage: "person.2.fill")
                }
                LabeledContent {
                    Text("\(friendsViewModel.incomingRequests.count + friendsViewModel.outgoingRequests.count)")
                } label: {
                    Label("Pending requests", systemImage: "clock.badge.questionmark")
                }
            }

            Section {
                VStack(spacing: 12) {
                    QRCodeView(content: friendsViewModel.myInviteCode)
                        .frame(width: 160, height: 160)
                    Text(friendsViewModel.myInviteCode)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                ShareLink(item: "Add me on Jolt: @\(friendsViewModel.myHandle)") {
                    Label("Share my handle", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = friendsViewModel.myHandle
                } label: {
                    Label("Copy handle", systemImage: "doc.on.doc")
                }
            } header: {
                Text("Invite")
            } footer: {
                Text("Anyone with this handle, code, or QR can send you a friend request.")
            }

            Section {
                LabeledContent {
                    Text(pavlokViewModel.account?.displayName ?? "Not signed in")
                } label: {
                    Label("Pavlok account", systemImage: "person.crop.circle.badge.checkmark")
                }
            } header: {
                Text("Linked accounts")
            } footer: {
                Text("Manage Pavlok sign-in from Settings → Account.")
            }

            Section {
                Button("Log out", role: .destructive) {
                    authViewModel.logOut()
                }
                .accessibilityIdentifier("profileLogOutButton")
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("profileScreen")
    }
}

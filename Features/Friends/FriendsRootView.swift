import SwiftUI

struct FriendsRootView: View {
    @Environment(AppDependencies.self) private var dependencies
    @State private var authViewModel: AuthViewModel?

    var body: some View {
        // NB: this must stay wrapped in a real container — a bare
        // `Group { if/else }.task { }` as the *direct* child of a
        // `.tabItem` fails to switch tabs at all in this SwiftUI runtime
        // (confirmed by bisection). Using VStack rather than NavigationStack
        // because FriendsListView/AuthView already provide their own.
        VStack {
            if let authViewModel {
                if authViewModel.currentUser != nil {
                    FriendsListView(authViewModel: authViewModel)
                } else {
                    AuthView(viewModel: authViewModel)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            if authViewModel == nil {
                authViewModel = AuthViewModel(repository: dependencies.authRepository)
            }
        }
    }
}

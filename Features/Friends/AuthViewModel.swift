import Foundation
import Observation

@MainActor
@Observable
final class AuthViewModel {
    private let repository: AuthRepository

    private(set) var currentUser: User?
    private(set) var isBusy = false
    var lastError: String?

    @ObservationIgnored
    nonisolated(unsafe) private var observationTask: Task<Void, Never>?

    init(repository: AuthRepository) {
        self.repository = repository
        observationTask = Task { [weak self] in
            guard let self else { return }
            for await user in repository.currentUser {
                self.currentUser = user
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    func signUp(email: String, password: String, handle: String, displayName: String) {
        isBusy = true
        lastError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false }
            do {
                try await repository.signUp(email: email, password: password, handle: handle, displayName: displayName)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func logIn(email: String, password: String) {
        isBusy = true
        lastError = nil
        Task { [weak self] in
            guard let self else { return }
            defer { isBusy = false }
            do {
                try await repository.logIn(email: email, password: password)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func logOut() {
        Task { await repository.logOut() }
    }
}

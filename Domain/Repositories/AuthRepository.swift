import Foundation

@MainActor
protocol AuthRepository {
    var currentUser: AsyncStream<User?> { get }
    func signUp(email: String, password: String, handle: String, displayName: String) async throws
    func logIn(email: String, password: String) async throws
    func logOut() async
    /// Associates this device's APNs token with the signed-in account so
    /// the (future) server can address pokes to it. Mock: no-op.
    func registerPushToken(_ token: String) async
}

import Foundation

struct User: Identifiable, Codable, Equatable {
    var id: UUID
    /// Unique, lowercase, no `@` prefix stored — the UI adds it for display.
    var handle: String
    var displayName: String
    var email: String
}

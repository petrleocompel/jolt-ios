import Foundation

/// Which Jolt Server the app talks to.
///
/// Jolt Server is self-hostable (see the server repo's `docs/SELFHOSTING.md`),
/// so the base URL is a user setting rather than a constant. Accounts do not
/// transfer between servers — each instance owns its own users, friend graph
/// and poke history — so changing this signs the user out.
struct ServerConfiguration: Equatable, Codable {
    /// Full API base, including the `/api/v1` path. Stored verbatim rather
    /// than reassembled from an origin, so an instance that mounts the API
    /// somewhere unusual behind a reverse proxy still works.
    var baseURL: URL

    /// Where a fresh install points. Comes from the `JoltDefaultServerURL`
    /// Info.plist key, i.e. the `JOLT_DEFAULT_SERVER_URL` build setting, so
    /// each build (or self-builder) picks its own instance without a code
    /// change.
    static let `default` = bundledDefault(
        from: Bundle.main.object(forInfoDictionaryKey: "JoltDefaultServerURL")
    )

    /// Used when the build doesn't set a usable URL: an obvious placeholder
    /// the user replaces under Settings → Server.
    static let placeholder = ServerConfiguration(
        baseURL: URL(string: "https://jolt.example.com/api/v1")!
    )

    static func bundledDefault(from infoValue: Any?) -> ServerConfiguration {
        guard let string = infoValue as? String,
              case .success(let config) = parse(string) else { return placeholder }
        return config
    }

    /// Parses user input into a configuration, or explains why it can't.
    ///
    /// Deliberately strict about the scheme: iOS App Transport Security
    /// blocks plain HTTP, so a `http://` URL would fail at request time with
    /// an opaque `NSURLErrorAppTransportSecurityRequiresSecureConnection`
    /// rather than anything the user could act on. Better to say so here.
    static func parse(_ input: String) -> Result<ServerConfiguration, ValidationError> {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        // A trailing slash would produce `//friends` when paths are appended.
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed

        guard let url = URL(string: normalized), let scheme = url.scheme?.lowercased() else {
            return .failure(.malformed)
        }
        guard url.host?.isEmpty == false else { return .failure(.malformed) }
        guard scheme == "https" else { return .failure(.insecureScheme) }
        return .success(ServerConfiguration(baseURL: url))
    }

    enum ValidationError: LocalizedError, Equatable {
        case empty
        case malformed
        case insecureScheme

        var errorDescription: String? {
            switch self {
            case .empty: return "Enter a server URL."
            case .malformed: return "That doesn't look like a URL."
            case .insecureScheme: return "The URL must start with https:// — iOS blocks plain HTTP."
            }
        }
    }
}

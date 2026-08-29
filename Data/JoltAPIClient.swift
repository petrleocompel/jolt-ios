import Foundation

/// Thin HTTP client for the Jolt Server contract (`openapi/jolt-v1.yaml`).
///
/// Knows about transport only — URLs, JSON, status codes, the bearer token.
/// Mapping the contract onto the app's repository protocols is
/// `HTTPSocialBackend`'s job.
actor JoltAPIClient {
    enum APIError: LocalizedError, Equatable {
        /// The server answered with a JSON `Error` body.
        case server(status: Int, message: String)
        /// 401 — token missing, expired, or issued by a different server.
        case unauthorized
        /// Reached something, but it wasn't a Jolt Server speaking JSON.
        case notJolt
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .server(_, let message): return message
            case .unauthorized: return "Your session has expired. Sign in again."
            case .notJolt: return "That URL didn't respond like a Jolt server. Check the address includes /api/v1."
            case .transport(let detail): return detail
            }
        }
    }

    private let configuration: ServerConfiguration
    private let session: URLSession
    private var token: String?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // The server emits RFC 3339 with fractional seconds on some fields and
        // without on others; `.iso8601` alone rejects the fractional form.
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: text) ?? plain.date(from: text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognised date: \(text)")
            )
        }
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    init(configuration: ServerConfiguration, token: String?, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.token = token
    }

    func setToken(_ token: String?) {
        self.token = token
    }

    // MARK: - Requests

    @discardableResult
    func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        body: (some Encodable)? = Optional<Never>.none,
        query: [String: String] = [:]
    ) async throws -> Response {
        let data = try await perform(method, path, body: body, query: query)
        guard !data.isEmpty else {
            throw APIError.notJolt
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.notJolt
        }
    }

    /// For endpoints that answer `204 No Content`.
    func sendIgnoringResponse(
        _ method: String,
        _ path: String,
        body: (some Encodable)? = Optional<Never>.none
    ) async throws {
        _ = try await perform(method, path, body: body, query: [:])
    }

    private func perform(
        _ method: String,
        _ path: String,
        body: (some Encodable)?,
        query: [String: String]
    ) async throws -> Data {
        // `appending(path:)` rather than string concatenation: it keeps any
        // base path (`/api/v1`) intact, which `URL(string:relativeTo:)` would
        // discard for a leading-slash path.
        var url = configuration.baseURL.appending(path: path)
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components?.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.notJolt }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        default:
            throw APIError.server(status: http.statusCode, message: Self.message(from: data, decoder: decoder))
        }
    }

    /// Pulls `{ "message": ... }` out of an error body, falling back to
    /// something readable when the body isn't the contract's `Error` shape
    /// (a proxy's HTML 502 page, most likely).
    private static func message(from data: Data, decoder: JSONDecoder) -> String {
        struct ErrorBody: Decodable { let message: String }
        if let body = try? decoder.decode(ErrorBody.self, from: data), !body.message.isEmpty {
            return body.message
        }
        return "The server rejected that request."
    }
}

// MARK: - Reachability

extension JoltAPIClient {
    /// Probes the server behind `configuration` without needing credentials.
    ///
    /// Hits `/me`, which is the cheapest authenticated endpoint: a Jolt
    /// Server answers `401` for it without a token, and anything that is
    /// *not* a Jolt Server almost certainly won't. A 401 is therefore a
    /// success signal here, not a failure.
    static func probe(_ configuration: ServerConfiguration, session: URLSession = .shared) async -> Result<Void, APIError> {
        var request = URLRequest(url: configuration.baseURL.appending(path: "me"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.notJolt) }
            switch http.statusCode {
            case 200, 401: return .success(())
            case 404: return .failure(.notJolt)
            default: return .failure(.server(status: http.statusCode, message: "Server answered \(http.statusCode)."))
            }
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }
}

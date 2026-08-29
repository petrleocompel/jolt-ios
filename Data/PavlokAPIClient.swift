import Foundation

/// HTTP client for a **Pavlok account** (`api.pavlok.com/api/v5`).
///
/// Every endpoint and response shape here was verified against a real account
/// — see `docs/PAVLOK-API.md`, which also records the two things that caught
/// us out: login credentials must be nested under `user`, and the returned JWT
/// lives at `user.token` rather than the top level.
///
/// Transport only. `PavlokBackend` maps this onto the app's own types.
actor PavlokAPIClient {
    enum APIError: LocalizedError, Equatable {
        case unauthorized
        case server(status: Int, message: String)
        case transport(String)
        case notPavlok

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "Your Pavlok session has expired. Sign in again."
            case .server(_, let message):
                return message
            case .transport(let detail):
                return detail
            case .notPavlok:
                return "That didn't look like the Pavlok API."
            }
        }
    }

    static let defaultBaseURL = URL(string: "https://api.pavlok.com/api/v5")!

    private let baseURL: URL
    private let session: URLSession
    private var token: String?

    init(baseURL: URL = PavlokAPIClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func setToken(_ token: String?) { self.token = token }

    // MARK: Auth

    struct LoginResult: Equatable {
        var account: PavlokAccount
        var token: String
    }

    func login(email: String, password: String) async throws -> LoginResult {
        // Nested under "user" — a flat body is rejected with 422.
        let body: [String: Any] = ["user": ["email": email, "password": password]]
        let json = try await post("users/login", body: body, authorized: false)
        guard let user = json["user"] as? [String: Any],
              let token = user["token"] as? String,
              let id = user["id"] as? Int else {
            throw APIError.notPavlok
        }
        let account = PavlokAccount(
            userID: id,
            email: user["email"] as? String ?? email,
            firstName: user["firstName"] as? String,
            lastName: user["lastName"] as? String
        )
        return LoginResult(account: account, token: token)
    }

    // MARK: Friends

    func friends() async throws -> [PavlokFriend] {
        let json = try await get("friendships/get-friends")
        let users = json["users"] as? [[String: Any]] ?? []
        return users.compactMap { Self.friend(from: $0) }
    }

    /// What each friend allows *me* to send them. Keyed by friend id.
    ///
    /// Reads `/poke-permissions/received`: the grants whose `userId` is the
    /// friend and whose `friendId` is me. The composer uses this to decide
    /// which stimulus buttons to offer.
    func receivedPokePermissions() async throws -> [Int: PavlokPokePermission] {
        let json = try await get("poke-permissions/received")
        let rows = json["pokePermissions"] as? [[String: Any]] ?? []
        var result: [Int: PavlokPokePermission] = [:]
        for row in rows {
            // On `/received`, `userId` is the granting friend.
            guard let granter = row["userId"] as? Int else { continue }
            result[granter] = PavlokPokePermission(
                friendID: granter,
                canVibrate: row["canVibrate"] as? Bool ?? false,
                canChime: row["canChime"] as? Bool ?? false,
                canZap: row["canZap"] as? Bool ?? false,
                maxZapValue: row["maxZapValue"] as? Int ?? 0
            )
        }
        return result
    }

    // MARK: Poking

    /// Sends a poke. The caller is responsible for having checked the
    /// recipient's permission — the server enforces it too, but a rejected
    /// poke is a worse experience than a disabled button.
    func sendPoke(to friendID: Int, stimulus: StimulusConfig) async throws {
        let body: [String: Any] = [
            "stimulus": [
                "type": Self.stimulusName(stimulus.kind),
                "intensity": stimulus.intensity,
                "count": stimulus.repetitions
            ]
        ]
        _ = try await post("pokes/send/user/\(friendID)", body: body, authorized: true)
    }

    /// Pavlok's stimulus vocabulary: `Zap` / `Beep` / `Vibe`, matching the
    /// `types=` filter the journal endpoint accepts.
    static func stimulusName(_ kind: StimulusKind) -> String {
        switch kind {
        case .zap: return "Zap"
        case .beep: return "Beep"
        case .vibe: return "Vibe"
        }
    }

    // MARK: Devices + stimulus journal

    struct PavlokDeviceRecord: Equatable {
        var id: Int
        var macAddress: String
        var name: String
    }

    func devices() async throws -> [PavlokDeviceRecord] {
        let json = try await get("user-devices/")
        let rows = json["devices"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? Int,
                  let mac = row["macAddress"] as? String else { return nil }
            return PavlokDeviceRecord(id: id, macAddress: mac, name: row["name"] as? String ?? "Pavlok")
        }
    }

    /// The device's own uploaded log. **No sender attribution** — see
    /// `docs/PAVLOK-API.md`. `macAddress` is the bare hex form reported by
    /// `/user-devices/`; the endpoint 422s without it.
    func stimulusJournal(macAddress: String, page: Int = 1, pageSize: Int = 25) async throws -> [PavlokStimulusLogEntry] {
        var items: [URLQueryItem] = [
            .init(name: "mac_address", value: macAddress),
            .init(name: "page", value: String(page)),
            .init(name: "page_size", value: String(pageSize))
        ]
        // Repeated `types` params, exactly as the official app sends them.
        for type in ["Zap", "Beep", "Vibe"] {
            items.append(.init(name: "types", value: type))
        }
        let json = try await get("diagnostic_logs/", query: items)
        let rows = json["items"] as? [[String: Any]] ?? []
        return rows.enumerated().compactMap { index, row in
            guard let stamp = row["ts"] as? String, let date = Self.date(from: stamp) else { return nil }
            let name = row["name"] as? String ?? "?"
            // `id` comes back as 0 for every row, so it cannot be the identity.
            return PavlokStimulusLogEntry(
                id: "\(stamp)-\(name)-\(index)",
                kind: Self.stimulusKind(named: name),
                rawName: name,
                timestamp: date
            )
        }
    }

    static func stimulusKind(named name: String) -> StimulusKind? {
        switch name.lowercased() {
        case "zap": return .zap
        case "beep", "chime": return .beep
        case "vibe", "vibrate", "motor": return .vibe
        default: return nil
        }
    }

    // MARK: Transport

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Timestamps come back both with and without fractional seconds
    /// (`…T17:15:17Z` and `…T09:54:13.500000Z`), so both are accepted.
    static func date(from text: String) -> Date? {
        fractionalFormatter.date(from: text) ?? plainFormatter.date(from: text)
    }

    private static func friend(from row: [String: Any]) -> PavlokFriend? {
        guard let id = row["id"] as? Int else { return nil }
        return PavlokFriend(
            id: id,
            firstName: row["firstName"] as? String,
            lastName: row["lastName"] as? String,
            username: row["username"] as? String,
            profilePictureURL: (row["profilePictureUrl"] as? String).flatMap(URL.init(string:))
        )
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw APIError.transport("Bad URL for \(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await send(request, authorized: true)
    }

    private func post(_ path: String, body: [String: Any], authorized: Bool) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request, authorized: authorized)
    }

    private func send(_ request: URLRequest, authorized: Bool) async throws -> [String: Any] {
        var request = request
        if authorized {
            guard let token else { throw APIError.unauthorized }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.notPavlok }
        if http.statusCode == 401 { throw APIError.unauthorized }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.server(status: http.statusCode, message: Self.errorMessage(from: json, status: http.statusCode))
        }
        return json ?? [:]
    }

    /// Pavlok reports errors as `{"errors": [...]}`, where the entries are
    /// either plain strings (`["Timestamp must be without timezone"]`) or
    /// FastAPI validation objects (`[{"loc":…, "msg":…}]`).
    static func errorMessage(from json: [String: Any]?, status: Int) -> String {
        guard let errors = json?["errors"] as? [Any], !errors.isEmpty else {
            return "Pavlok returned HTTP \(status)."
        }
        let parts: [String] = errors.compactMap { entry in
            if let text = entry as? String { return text }
            if let object = entry as? [String: Any] {
                let field = (object["loc"] as? [Any])?.compactMap { $0 as? String }.last
                let message = object["msg"] as? String ?? "invalid"
                return field.map { "\($0): \(message)" } ?? message
            }
            return nil
        }
        return parts.isEmpty ? "Pavlok returned HTTP \(status)." : parts.joined(separator: ", ")
    }
}

import Foundation

public enum ClientError: Error, Equatable, LocalizedError {
    /// The address isn't one a server could be at.
    case badAddress
    /// The server turned the sign in down even after fresh tokens.
    case notSignedIn
    /// The sign in has run out or been revoked, so the person has to sign in again.
    case signedOut
    /// What the person signed in as isn't allowed to do this. Holds what the server
    /// said, if it said anything.
    case notAllowed(String?)
    case status(Int)
    /// Something answered, but not as a MaxNines server does.
    case notMaxNines
    /// The alert's rule has been deleted, so a silence can't name it.
    case cantSilence

    public var errorDescription: String? {
        switch self {
        case .badAddress: "The server address isn't a web address"
        case .notSignedIn: "The server didn't accept the sign in"
        case .signedOut: "Signed out: sign in again"
        case .notAllowed(let said?): said
        case .notAllowed(nil): "This sign in isn't allowed to do that. Acknowledging and silencing need the responder role"
        case .status(let code): "The server answered with status \(code)"
        case .notMaxNines: "That address didn't answer like a MaxNines server"
        case .cantSilence: "This alert's rule has been deleted, so it can't be silenced from here"
        }
    }
}

/// Sends a request and gives back the answer. `URLSession` in the app, and
/// something that answers by itself in the tests.
public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

public let urlSessionTransport: Transport = { try await URLSession.shared.data(for: $0) }

/// Where a MaxNines server is: the root of the site, whatever page of it was
/// pasted.
public struct ServerAddress: Equatable, Sendable {
    public let url: URL

    /// `typed` is what someone types: the address they open MaxNines at.
    public init(_ typed: String) throws {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), url.host() != nil
        else {
            throw ClientError.badAddress
        }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let root = parts.url else { throw ClientError.badAddress }
        self.url = root
    }

    /// A page of the web interface, such as `/alerts`.
    public func page(_ path: String) -> URL {
        url.appending(path: path)
    }

    /// Whether what the app sends crosses the network unencrypted to somewhere
    /// other than this Mac.
    public var isInTheClear: Bool {
        let host = url.host() ?? ""
        return url.scheme == "http" && !["localhost", "127.0.0.1", "::1"].contains(host)
    }
}

/// Something that hands out access tokens: a `TokenHolder` in the app.
public protocol AccessTokens: Sendable {
    /// One that works, as far as is known.
    func accessToken() async throws -> String
    /// A newer one than `rejected`, which the server just turned down.
    func accessToken(replacing rejected: String) async throws -> String
}

/// Talks to one MaxNines server's API as whoever signed in.
public struct Client: Sendable {
    public let server: ServerAddress
    let tokens: any AccessTokens
    let transport: Transport

    public init(server: ServerAddress, tokens: any AccessTokens, transport: @escaping Transport = urlSessionTransport) {
        self.server = server
        self.tokens = tokens
        self.transport = transport
    }

    /// A page of the web interface, such as `/alerts`.
    public func page(_ path: String) -> URL {
        server.page(path)
    }

    func request(_ method: String, _ path: String, body: Data? = nil, token: String) -> URLRequest {
        var request = URLRequest(url: server.url.appending(path: "api/v1").appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Sends a request with the access token. If the server turns the token down,
    /// it gets a newer one and tries once more.
    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        let token = try await tokens.accessToken()
        var (data, status) = try await attempt(request(method, path, body: body, token: token))
        if status == 401 {
            let newer = try await tokens.accessToken(replacing: token)
            (data, status) = try await attempt(request(method, path, body: body, token: newer))
        }
        switch status {
        case 200..<300: return data
        case 401: throw ClientError.notSignedIn
        case 403: throw ClientError.notAllowed(Client.said(in: data))
        default: throw ClientError.status(status)
        }
    }

    private func attempt(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.notMaxNines }
        return (data, response.statusCode)
    }

    /// What the server said went wrong, in an answer like `{"error": "…"}`.
    static func said(in data: Data) -> String? {
        struct Said: Decodable { let error: String }
        return try? decoder.decode(Said.self, from: data).error
    }

    private func get<Answer: Decodable>(_ path: String) async throws -> Answer {
        let data = try await send("GET", path)
        do {
            return try Client.decoder.decode(Answer.self, from: data)
        } catch {
            throw ClientError.notMaxNines
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            let text = try value.decode(String.self)
            guard let date = Client.moment(text) else {
                throw DecodingError.dataCorruptedError(
                    in: value, debugDescription: "\(text) isn't an ISO 8601 time")
            }
            return date
        }
        return decoder
    }()

    /// A moment as the server gives it, an ISO 8601 time in UTC such as
    /// `2026-11-19T01:57:17.828Z`. The server leaves the fraction out when the
    /// milliseconds are zero, and a format that expects a fraction won't read a
    /// time without one, nor the other way round, so both are tried.
    static func moment(_ text: String) -> Date? {
        let withMilliseconds = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withMilliseconds.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    public func alerts() async throws -> Alerts {
        try await get("alerts")
    }

    public func hosts() async throws -> [MonitoredHost] {
        try await get("hosts")
    }

    public func silences() async throws -> Silences {
        try await get("silences")
    }

    public func remoteChecks() async throws -> [RemoteCheck] {
        try await get("remote-checks")
    }

    /// Says whoever signed in is dealing with an alert.
    public func acknowledge(alertID: Int) async throws {
        _ = try await send("POST", "alerts/\(alertID)/acknowledge")
    }

    /// Keeps an alert's notifications back for a while.
    public func silence(_ alert: ServerAlert, for duration: TimeInterval) async throws {
        _ = try await send("POST", "silences", body: Client.silenceBody(alert, for: duration))
    }

    /// A silence for this alert and nothing else: its rule, on its host, for its
    /// series. An alert about a group of hosts belongs to no one host, so it has no
    /// filter, which the server takes to mean it alone.
    static func silenceBody(_ alert: ServerAlert, for duration: TimeInterval) throws -> Data {
        // Without a rule the silence would cover every rule.
        guard let rule = alert.ruleId else { throw ClientError.cantSilence }
        var body: [String: Any] = [
            "reason": "Silenced from the menu bar",
            "duration_secs": Int(duration),
            "rule_id": rule,
        ]
        if alert.hostId != "fleet" {
            body["filter"] = "id=\(alert.hostId)"
        }
        if let series = alert.series {
            body["series"] = series
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

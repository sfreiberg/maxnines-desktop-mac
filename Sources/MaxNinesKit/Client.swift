import Foundation

public enum ClientError: Error, Equatable, LocalizedError {
    /// The address isn't one a server could be at.
    case badAddress
    /// The key is wrong, revoked or expired, or its owner is disabled.
    case notSignedIn
    /// The key's role doesn't allow this.
    case notAllowed
    case status(Int)
    /// Something answered, but not as a MaxNines server does.
    case notMaxNines
    /// The alert's rule has been deleted, so a silence can't name it.
    case cantSilence

    public var errorDescription: String? {
        switch self {
        case .badAddress: "The server address isn't a web address"
        case .notSignedIn: "The server didn't accept the API key"
        case .notAllowed: "This API key isn't allowed to do that. Acknowledging and silencing need a responder key"
        case .status(let code): "The server answered with status \(code)"
        case .notMaxNines: "That address didn't answer like a MaxNines server"
        case .cantSilence: "This alert's rule has been deleted, so it can't be silenced from here"
        }
    }
}

/// Talks to one MaxNines server's API as the owner of an API key.
public struct Client: Sendable {
    public let server: URL
    let apiKey: String
    let session: URLSession

    /// `address` is what someone types: the address they open MaxNines at.
    public init(address: String, apiKey: String, session: URLSession = .shared) throws {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme), url.host() != nil
        else {
            throw ClientError.badAddress
        }
        // Whatever page of the site was pasted, the API is at its root.
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let server = parts.url else { throw ClientError.badAddress }
        self.server = server
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    /// A page of the web interface, such as `/alerts`.
    public func page(_ path: String) -> URL {
        server.appending(path: path)
    }

    /// Whether the key crosses the network unencrypted to somewhere other than
    /// this Mac.
    public var sendsKeyInTheClear: Bool {
        let host = server.host() ?? ""
        return server.scheme == "http" && !["localhost", "127.0.0.1", "::1"].contains(host)
    }

    func request(_ method: String, _ path: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: server.appending(path: "api/v1").appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.notMaxNines }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw ClientError.notSignedIn
        case 403: throw ClientError.notAllowed
        default: throw ClientError.status(response.statusCode)
        }
    }

    private func get<Answer: Decodable>(_ path: String) async throws -> Answer {
        let data = try await send(request("GET", path))
        do {
            return try Client.decoder.decode(Answer.self, from: data)
        } catch {
            throw ClientError.notMaxNines
        }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

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

    /// Says the key's owner is dealing with an alert.
    public func acknowledge(alertID: Int) async throws {
        _ = try await send(request("POST", "alerts/\(alertID)/acknowledge"))
    }

    /// Keeps an alert's notifications back for a while.
    public func silence(_ alert: ServerAlert, for duration: TimeInterval) async throws {
        _ = try await send(request("POST", "silences", body: Client.silenceBody(alert, for: duration)))
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
        if let series = alert.series, !series.isEmpty {
            body["series"] = series
        }
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }
}

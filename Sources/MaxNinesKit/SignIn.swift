import CryptoKit
import Foundation

/// Signing in through the browser, as the server's "Signing in apps" documentation
/// describes: the person approves the app on a MaxNines page, and the browser
/// brings an approval back to this Mac, which the app swaps for tokens.

/// What the server knows this app as.
public let clientID = "maxnines-desktop-mac"

/// The most the app asks for: enough to acknowledge and silence. The person can
/// choose less.
public let askedRole = "responder"

/// A one-time secret that proves the approval coming back is for the app that
/// asked for it, as RFC 7636 describes.
public struct PKCE: Sendable {
    /// Kept by the app, and sent only when swapping the approval for tokens.
    public let verifier: String
    /// Sent when asking, as the SHA-256 of the verifier.
    public let challenge: String

    public init() {
        self.init(verifier: randomText(bytes: 32))
    }

    init(verifier: String) {
        self.verifier = verifier
        self.challenge = PKCE.challenge(for: verifier)
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// Random bytes in base64url, which uses only characters a URL leaves alone.
func randomText(bytes: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    return base64URL(Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
}

func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// Fields as a form or a query sends them. Everything but the characters that
/// never need it is escaped, `+` included, which would otherwise be read as a space.
func formEncoded(_ fields: [(String, String)]) -> String {
    var safe = CharacterSet.alphanumerics.intersection(.init(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
    safe.insert(charactersIn: "-._~")
    let escape = { (text: String) in text.addingPercentEncoding(withAllowedCharacters: safe) ?? "" }
    return fields.map { "\(escape($0))=\(escape($1))" }.joined(separator: "&")
}

/// One attempt at signing in: what's sent to the browser, and how to read what
/// comes back.
public struct BrowserSignIn: Sendable {
    public let server: ServerAddress
    /// Where the browser comes back to, on this Mac.
    public let redirectURI: String
    /// The computer's name, shown when approving and in the server's list of
    /// signed-in apps.
    public let device: String
    public let pkce: PKCE
    /// Sent and given back unchanged, so an answer to some other request is
    /// turned away.
    public let state: String

    public static let callbackPath = "/callback"

    public init(server: ServerAddress, port: UInt16, device: String) {
        self.init(server: server, port: port, device: device, pkce: PKCE(), state: randomText(bytes: 16))
    }

    init(server: ServerAddress, port: UInt16, device: String, pkce: PKCE, state: String) {
        self.server = server
        self.redirectURI = "http://127.0.0.1:\(port)\(BrowserSignIn.callbackPath)"
        // The server takes up to 100 characters, with no control characters.
        let visible = device.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
            .filter { $0.properties.generalCategory != .control }
        self.device = String(String.UnicodeScalarView(visible.prefix(100)))
        self.pkce = pkce
        self.state = state
    }

    /// The page the browser opens for the person to approve the app.
    public var authorizeURL: URL {
        let query = formEncoded([
            ("response_type", "code"),
            ("client_id", clientID),
            ("redirect_uri", redirectURI),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"),
            ("state", state),
            ("device", device),
            ("role", askedRole),
        ])
        return URL(string: "\(server.page("oauth/authorize").absoluteString)?\(query)")!
    }

    /// What the browser brought back, read from the first line of its request,
    /// such as `GET /callback?code=…&state=… HTTP/1.1`. Nil for a request that
    /// isn't the answer to this sign in: another path, or another `state`.
    public func answer(fromRequestLine line: String) -> Answer? {
        let words = line.split(separator: " ")
        guard words.count >= 2, words[0] == "GET",
            let parts = URLComponents(string: String(words[1])),
            parts.path == BrowserSignIn.callbackPath
        else {
            return nil
        }
        var fields: [String: String] = [:]
        for item in parts.queryItems ?? [] {
            // A form sends a space as `+`, which URLComponents leaves alone.
            fields[item.name] = item.value?.replacingOccurrences(of: "+", with: " ")
        }
        guard fields["state"] == state else { return nil }
        if let code = fields["code"], !code.isEmpty {
            return .code(code)
        }
        return fields["error"] == "access_denied" ? .denied : .failed(fields["error"] ?? "no code")
    }

    public enum Answer: Equatable, Sendable {
        case code(String)
        /// The person chose Deny.
        case denied
        /// The server couldn't ask, saying why in OAuth's words.
        case failed(String)
    }
}

/// What the server gives for an approval or a refresh token.
public struct Tokens: Decodable, Equatable, Sendable {
    public let accessToken: String
    /// Seconds the access token works for.
    public let expiresIn: Int
    public let refreshToken: String
    /// What the app acts as, which the person may have chosen lower than asked.
    public let role: String
    /// The email address of who signed in.
    public let user: String

    public init(accessToken: String, expiresIn: Int, refreshToken: String, role: String, user: String) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.role = role
        self.user = user
    }
}

/// The server's sign in endpoints, which apps call with what they hold rather
/// than a token.
public struct SignInEndpoints: Sendable {
    public let server: ServerAddress
    let transport: Transport

    public init(server: ServerAddress, transport: @escaping Transport = urlSessionTransport) {
        self.server = server
        self.transport = transport
    }

    /// Swaps an approval for tokens.
    public func tokens(code: String, signIn: BrowserSignIn) async throws -> Tokens {
        try await post(
            "oauth/token",
            [
                ("grant_type", "authorization_code"),
                ("client_id", clientID),
                ("code", code),
                ("redirect_uri", signIn.redirectURI),
                ("code_verifier", signIn.pkce.verifier),
            ])
    }

    /// Swaps a refresh token for new tokens. The old refresh token stops working.
    /// Throws `ClientError.signedOut` when the sign in has run out or been revoked.
    public func refresh(_ refreshToken: String) async throws -> Tokens {
        do {
            return try await post(
                "oauth/token",
                [("grant_type", "refresh_token"), ("client_id", clientID), ("refresh_token", refreshToken)])
        } catch OAuthError.said("invalid_grant", _) {
            throw ClientError.signedOut
        }
    }

    /// Signs the app out on the server. Either token works.
    public func revoke(_ token: String) async throws {
        let (_, status) = try await send("oauth/revoke", [("client_id", clientID), ("token", token)])
        guard status == 200 else { throw ClientError.status(status) }
    }

    private func post(_ path: String, _ fields: [(String, String)]) async throws -> Tokens {
        let (data, status) = try await send(path, fields)
        guard status == 200 else {
            if let said = try? Client.decoder.decode(OAuthAnswer.self, from: data) {
                throw OAuthError.said(said.error, said.errorDescription ?? said.error)
            }
            throw ClientError.status(status)
        }
        do {
            return try Client.decoder.decode(Tokens.self, from: data)
        } catch {
            throw ClientError.notMaxNines
        }
    }

    private func send(_ path: String, _ fields: [(String, String)]) async throws -> (Data, Int) {
        var request = URLRequest(url: server.url.appending(path: path))
        request.httpMethod = "POST"
        // Short, so a refresh that gets no answer can be tried again while the server
        // still takes the refresh token: see TokenHolder.retryWindow.
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(formEncoded(fields).utf8)
        let (data, response) = try await transport(request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.notMaxNines }
        return (data, response.statusCode)
    }
}

/// How the sign in endpoints answer when they turn something down.
struct OAuthAnswer: Decodable {
    let error: String
    let errorDescription: String?
}

/// The sign in endpoints turned something down: OAuth's word for it, and the
/// server's explanation.
public enum OAuthError: Error, Equatable, LocalizedError {
    case said(String, String)

    public var errorDescription: String? {
        switch self {
        case .said(_, let description): description
        }
    }
}

import Foundation
import Network

/// Why signing in through the browser didn't finish.
public enum SignInError: Error, Equatable, LocalizedError {
    /// The person chose Deny.
    case denied
    /// The server couldn't ask the person, in OAuth's words.
    case failed(String)
    /// Nothing came back from the browser in time.
    case timedOut
    /// Cancelled once the server had signed the app in, and the server couldn't
    /// then be told to sign it out.
    case cancelledNotRevoked

    public var errorDescription: String? {
        switch self {
        case .denied: "You chose Deny, so the app isn't signed in"
        case .failed(let error): "The server couldn't ask you to sign in (\(error))"
        case .timedOut: "Nothing came back from the browser, so the app isn't signed in. Try again"
        case .cancelledNotRevoked:
            "Signing in was cancelled, but the server couldn't be told. Revoke it in MaxNines under Settings, then Signed-in apps"
        }
    }
}

/// Signs in through the browser: listens on this Mac for the browser to come
/// back, has `open` show the person the server's approval page, swaps the
/// approval for tokens, and tells the person in the browser how it went.
/// Gives up after `timeout` without an answer from the browser, or when the task
/// is cancelled.
public func signInThroughBrowser(
    server: ServerAddress, device: String, open: @escaping @Sendable (URL) async -> Void,
    transport: @escaping Transport = urlSessionTransport, timeout: Duration = .seconds(300)
) async throws -> Tokens {
    let loopback = try Loopback()
    defer { loopback.stop() }
    let port = try await loopback.start()
    let signIn = BrowserSignIn(server: server, port: port, device: device)
    let endpoints = SignInEndpoints(server: server, transport: transport)
    await open(signIn.authorizeURL)
    let (request, answer) = try await withTimeout(timeout) {
        for try await request in loopback.requests {
            // Anything else the browser asks for, such as an icon, or an answer
            // to some other request, isn't the one being waited for.
            guard let answer = signIn.answer(fromRequestLine: request.line) else {
                request.respond(status: 404, page: resultPage("Not found", ""))
                continue
            }
            return (request, answer)
        }
        throw CancellationError()
    }
    do {
        switch answer {
        case .denied: throw SignInError.denied
        case .failed(let error): throw SignInError.failed(error)
        case .code(let code):
            // Once the server has the code it may give tokens, so the swap is seen
            // through even if signing in is cancelled meanwhile, and what it gives
            // is then revoked, so nothing is left signed in that nothing here holds.
            let tokens = try await Task { try await endpoints.tokens(code: code, signIn: signIn) }.value
            if Task.isCancelled {
                do {
                    try await endpoints.revoke(unwanted: tokens)
                } catch {
                    throw SignInError.cancelledNotRevoked
                }
                throw CancellationError()
            }
            request.respond(status: 200, page: resultPage("Signed in to MaxNines", "You can close this tab."))
            return tokens
        }
    } catch {
        let why = error is CancellationError ? "Signing in was cancelled in the app" : error.localizedDescription
        request.respond(status: 200, page: resultPage("Not signed in", "\(why). You can close this tab."))
        throw error
    }
}

/// Runs `work`, giving up with `SignInError.timedOut` after `timeout`.
func withTimeout<T: Sendable>(
    _ timeout: Duration, _ work: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await work() }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw SignInError.timedOut
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw CancellationError() }
        return first
    }
}

/// The page the browser shows once it's back.
func resultPage(_ title: String, _ detail: String) -> String {
    func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><title>\(escaped(title))</title>
        <style>
        body { margin: 0; min-height: 100vh; display: grid; place-items: center;
          font: 16px -apple-system, system-ui, sans-serif; background: #0f1214; color: #e6e9eb; }
        main { text-align: center; padding: 24px; }
        h1 { font-size: 22px; font-weight: 600; margin: 0 0 8px; }
        p { color: #9aa3a8; margin: 0; }
        </style></head>
        <body><main><h1>\(escaped(title))</h1><p>\(escaped(detail))</p></main></body></html>
        """
}

/// A request the browser made to the loopback listener.
struct LoopbackRequest: @unchecked Sendable {
    /// Its first line, such as `GET /callback?code=… HTTP/1.1`.
    let line: String
    private let connection: NWConnection

    init(line: String, connection: NWConnection) {
        self.line = line
        self.connection = connection
    }

    /// Answers with a page, then closes the connection.
    func respond(status: Int, page: String) {
        let body = Data(page.utf8)
        let reason = status == 200 ? "OK" : "Not Found"
        let head = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "", "",
        ].joined(separator: "\r\n")
        let connection = connection
        connection.send(
            content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() })
    }
}

/// Listens on a free port of 127.0.0.1, the address RFC 8252 asks for, as
/// `localhost` can be made to mean somewhere else. Only this Mac can reach it.
final class Loopback: @unchecked Sendable {
    let requests: AsyncThrowingStream<LoopbackRequest, Error>
    private let incoming: AsyncThrowingStream<LoopbackRequest, Error>.Continuation
    private let listener: NWListener
    /// Everything below happens on this queue.
    private let queue = DispatchQueue(label: "com.maxnines.menubar.loopback")
    private var ready: CheckedContinuation<UInt16, Error>?

    /// The most a request's head can be, which a browser's is well under.
    private static let biggestHead = 32 * 1024

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        (requests, incoming) = AsyncThrowingStream.makeStream()
    }

    /// Starts listening, and gives back the port it's on.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { ready in
            queue.async { [self] in
                self.ready = ready
                listener.stateUpdateHandler = { [weak self] state in self?.changed(to: state) }
                listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
                listener.start(queue: queue)
            }
        }
    }

    func stop() {
        listener.cancel()
        incoming.finish()
    }

    private func changed(to state: NWListener.State) {
        switch state {
        case .ready:
            if let port = listener.port?.rawValue {
                ready?.resume(returning: port)
                ready = nil
            }
        case .failed(let error):
            ready?.resume(throwing: error)
            ready = nil
            incoming.finish(throwing: error)
            listener.cancel()
        case .cancelled:
            ready?.resume(throwing: CancellationError())
            ready = nil
            incoming.finish()
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, Data())
    }

    /// Reads until the end of the request's head, so nothing's left unread when
    /// the answer closes the connection, which would reset it instead.
    private func read(_ connection: NWConnection, _ sofar: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, done, error in
            guard let self else { return }
            let head = sofar + (data ?? Data())
            if head.range(of: Data("\r\n\r\n".utf8)) != nil,
                let text = String(data: head, encoding: .utf8),
                let line = text.components(separatedBy: "\r\n").first
            {
                incoming.yield(LoopbackRequest(line: line, connection: connection))
            } else if error != nil || done || head.count > Loopback.biggestHead {
                connection.cancel()
            } else {
                read(connection, head)
            }
        }
    }
}

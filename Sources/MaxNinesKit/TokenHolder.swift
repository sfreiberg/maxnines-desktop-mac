import Foundation

/// Keeps the tokens of one sign in and hands out an access token that works.
///
/// The access token lives only in memory. The refresh token is handed to `save`
/// each time it changes, before the new access token is used, so what's kept is
/// always the newest: the server revokes the whole sign in if a refresh token it
/// has replaced is used again a minute later. For the same reason only one
/// refresh runs at a time, and everything that needs a token meanwhile waits for it.
public actor TokenHolder: AccessTokens {
    private let endpoints: SignInEndpoints
    /// Keeps tokens, or forgets them when given nil, as when signed out.
    private let save: @Sendable (Tokens?) -> Void
    private let now: @Sendable () -> Date
    private var refreshToken: String?
    private var access: (token: String, expires: Date)?
    /// The refresh running now, if one is.
    private var refreshing: Task<String, Error>?
    /// Set once signing out starts, after which nothing refreshes.
    private var signingOut = false

    /// How long before the access token runs out that a new one is fetched.
    static let early: TimeInterval = 60
    /// How long to wait before each new try when a refresh fails for any reason
    /// but being signed out. They all fall within the minute the server still
    /// takes a refresh token it has just replaced, so an answer lost on the way
    /// is asked for again in time, rather than at the next check, when reusing
    /// the token would get the whole sign in revoked.
    private let retryDelays: [TimeInterval]

    /// Just signed in, with tokens that `save` already has.
    public init(
        tokens: Tokens, endpoints: SignInEndpoints, save: @escaping @Sendable (Tokens?) -> Void,
        now: @escaping @Sendable () -> Date = { Date() }, retryDelays: [TimeInterval] = [2, 5, 15]
    ) {
        self.retryDelays = retryDelays
        self.endpoints = endpoints
        self.save = save
        self.now = now
        self.refreshToken = tokens.refreshToken
        self.access = (tokens.accessToken, now().addingTimeInterval(TimeInterval(tokens.expiresIn)))
    }

    /// Signed in earlier, with only the saved refresh token, so the first request
    /// refreshes.
    public init(
        refreshToken: String, endpoints: SignInEndpoints, save: @escaping @Sendable (Tokens?) -> Void,
        now: @escaping @Sendable () -> Date = { Date() }, retryDelays: [TimeInterval] = [2, 5, 15]
    ) {
        self.retryDelays = retryDelays
        self.endpoints = endpoints
        self.save = save
        self.now = now
        self.refreshToken = refreshToken
    }

    public func accessToken() async throws -> String {
        if let token = current() {
            return token
        }
        return try await refreshed()
    }

    public func accessToken(replacing rejected: String) async throws -> String {
        // Another request may have fetched a new one already.
        if let token = current(), token != rejected {
            return token
        }
        return try await refreshed()
    }

    /// Signs out: tells the server, and forgets the tokens whether or not it
    /// could be told. Throws when the server couldn't be told, so the person can
    /// be asked to revoke it there.
    public func signOut() async throws {
        signingOut = true
        // The server only revokes by its newest tokens, so a refresh running now
        // is let finish, and what it brings back is revoked.
        _ = try? await refreshing?.value
        let token = refreshToken ?? access?.token
        refreshToken = nil
        access = nil
        save(nil)
        if let token {
            try await endpoints.revoke(token)
        }
    }

    /// The access token, if it isn't about to run out.
    private func current() -> String? {
        guard let access, access.expires.timeIntervalSince(now()) > TokenHolder.early else { return nil }
        return access.token
    }

    /// Joins the refresh running now, or starts one.
    private func refreshed() async throws -> String {
        if let refreshing {
            return try await refreshing.value
        }
        let task = Task { try await self.refresh() }
        refreshing = task
        defer { refreshing = nil }
        return try await task.value
    }

    /// Swaps the refresh token, trying again soon if the answer doesn't come.
    private func refreshTrying(_ refreshToken: String) async throws -> Tokens {
        var delays = retryDelays[...]
        while true {
            do {
                return try await endpoints.refresh(refreshToken)
            } catch ClientError.signedOut {
                throw ClientError.signedOut
            } catch {
                guard let delay = delays.popFirst(), !signingOut else { throw error }
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private func refresh() async throws -> String {
        guard !signingOut, let refreshToken else { throw ClientError.signedOut }
        let tokens: Tokens
        do {
            tokens = try await refreshTrying(refreshToken)
        } catch ClientError.signedOut {
            // It's run out or been revoked, and won't work again.
            self.refreshToken = nil
            access = nil
            save(nil)
            throw ClientError.signedOut
        }
        // Kept before it's used, so a crash now can't leave the old one saved.
        save(tokens)
        self.refreshToken = tokens.refreshToken
        access = (tokens.accessToken, now().addingTimeInterval(TimeInterval(tokens.expiresIn)))
        return tokens.accessToken
    }
}

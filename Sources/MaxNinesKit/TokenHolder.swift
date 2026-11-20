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
    /// Keeps tokens, or forgets them when given nil, as when signed out, and
    /// says whether that worked.
    private let save: @Sendable (Tokens?) -> Bool
    /// The newest tokens, while `save` couldn't keep them. They're used all the
    /// same, as the server has already replaced the ones kept before, and saved
    /// again each time a token is asked for, until they're kept.
    private var unsaved: Tokens?
    private let now: @Sendable () -> Date
    private var refreshToken: String?
    /// The access token, when it runs out, and how long before then a new one
    /// is fetched.
    private var access: (token: String, expires: Date, early: TimeInterval)?
    /// The refresh running now, if one is.
    private var refreshing: Task<String, Error>?
    /// Set once signing out starts, after which nothing refreshes.
    private var signingOut = false

    /// How long before the access token runs out that a new one is fetched, or
    /// half of how long it works for when that's shorter, so it's used for a
    /// while however short its life.
    static let early: TimeInterval = 60

    static func early(lasting: Int) -> TimeInterval {
        min(early, TimeInterval(lasting) / 2)
    }
    /// How long to wait before each new try when a refresh fails for any reason
    /// but being signed out. They all fall within the minute the server still
    /// takes a refresh token it has just replaced, so an answer lost on the way
    /// is asked for again in time, rather than at the next check, when reusing
    /// the token would get the whole sign in revoked.
    private let retryDelays: [TimeInterval]

    /// Just signed in: `save` keeps the tokens before anything uses them.
    public init(
        tokens: Tokens, endpoints: SignInEndpoints, save: @escaping @Sendable (Tokens?) -> Bool,
        now: @escaping @Sendable () -> Date = { Date() }, retryDelays: [TimeInterval] = [2, 5, 15]
    ) {
        self.retryDelays = retryDelays
        self.endpoints = endpoints
        self.save = save
        self.now = now
        self.refreshToken = tokens.refreshToken
        self.access = TokenHolder.access(tokens, now: now())
        self.unsaved = save(tokens) ? nil : tokens
    }

    /// Signed in earlier, with only the saved refresh token, so the first request
    /// refreshes.
    public init(
        refreshToken: String, endpoints: SignInEndpoints, save: @escaping @Sendable (Tokens?) -> Bool,
        now: @escaping @Sendable () -> Date = { Date() }, retryDelays: [TimeInterval] = [2, 5, 15]
    ) {
        self.retryDelays = retryDelays
        self.endpoints = endpoints
        self.save = save
        self.now = now
        self.refreshToken = refreshToken
    }

    /// Whether the newest refresh token is kept, so it's what the app starts with
    /// next time. If it isn't, the next start would present one the server has
    /// replaced, and the server would revoke the whole sign in.
    public var isSaved: Bool {
        keepUnsaved()
        return unsaved == nil
    }

    public func accessToken() async throws -> String {
        keepUnsaved()
        if let token = current() {
            return token
        }
        return try await refreshed()
    }

    public func accessToken(replacing rejected: String) async throws -> String {
        keepUnsaved()
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
        unsaved = nil
        _ = save(nil)
        if let token {
            try await endpoints.revoke(token)
        }
    }

    /// Tries again to keep tokens `save` couldn't.
    private func keepUnsaved() {
        if let unsaved, save(unsaved) {
            self.unsaved = nil
        }
    }

    /// The access token, if it isn't about to run out.
    private func current() -> String? {
        guard let access, access.expires.timeIntervalSince(now()) > access.early else { return nil }
        return access.token
    }

    private static func access(_ tokens: Tokens, now: Date) -> (token: String, expires: Date, early: TimeInterval) {
        (tokens.accessToken, now.addingTimeInterval(TimeInterval(tokens.expiresIn)), early(lasting: tokens.expiresIn))
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

    /// How long after the first try a refresh may start another. The server takes a
    /// refresh token it has just replaced for a minute from when it replaced it, which is
    /// no earlier than the first try, so this leaves room for a slow network, however
    /// long each try waited for its answer.
    static let retryWindow: TimeInterval = 45

    /// Swaps the refresh token, trying again soon if the answer doesn't come.
    private func refreshTrying(_ refreshToken: String) async throws -> Tokens {
        var delays = retryDelays[...]
        let started = now()
        while true {
            do {
                return try await endpoints.refresh(refreshToken)
            } catch ClientError.signedOut {
                throw ClientError.signedOut
            } catch {
                guard let delay = delays.popFirst(), !signingOut,
                    now().timeIntervalSince(started) + delay < TokenHolder.retryWindow
                else { throw error }
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
            unsaved = nil
            _ = save(nil)
            throw ClientError.signedOut
        }
        // Kept before it's used, so a crash now can't leave the old one saved.
        unsaved = save(tokens) ? nil : tokens
        self.refreshToken = tokens.refreshToken
        access = TokenHolder.access(tokens, now: now())
        return tokens.accessToken
    }
}

/// Where the app keeps its sign in's refresh token, which only the newest sign in
/// may change. One signed out of or replaced may still be finishing a refresh or
/// a sign out, and mustn't overwrite or forget the token of the one after it.
public final class TokenSlot: @unchecked Sendable {
    /// Keeps a refresh token, or forgets it when given nil, and says whether that
    /// worked.
    private let write: @Sendable (String?) -> Bool
    private let lock = NSLock()
    private var newest = 0

    public init(write: @escaping @Sendable (String?) -> Bool) {
        self.write = write
    }

    /// Hands the slot to a new sign in, or to signing out. Gives back what it's
    /// saved with, and no earlier claim can change it after this.
    public func claim() -> Int {
        lock.withLock {
            newest += 1
            return newest
        }
    }

    /// Keeps `token`, or forgets it when nil, if `claim` is still the newest.
    /// Returns false only when it should have and couldn't.
    public func save(_ token: String?, for claim: Int) -> Bool {
        // Held while writing, so a claim can't come between the check and the write.
        lock.withLock { claim == newest ? write(token) : true }
    }
}

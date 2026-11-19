import AppKit
import MaxNinesKit
import SwiftUI
import SystemConfiguration

/// What the app knows: its settings, and what the server last said.
@MainActor
final class Store: ObservableObject {
    /// What the server last listed. Kept while a later try fails, as old news
    /// that says it's old beats none.
    @Published private(set) var overview: Overview?
    @Published private(set) var updated: Date?
    /// Why the server couldn't be asked, if it couldn't.
    @Published private(set) var problem: String?
    /// Why the last acknowledge or silence didn't work.
    @Published var actionProblem: String?
    @Published private(set) var address: String
    @Published private(set) var interval: Int
    /// Who's signed in, and as what, while the app is.
    @Published private(set) var account: Account?
    /// Whether it's waiting for the person to sign in in the browser.
    @Published private(set) var signingIn = false
    /// Why the last sign in or sign out didn't go as it should.
    @Published var signInProblem: String?
    /// Set while the Keychain won't keep the sign in's newest refresh token.
    @Published private(set) var saveProblem: String?

    private var client: Client?
    private var tokens: TokenHolder?
    /// Where the refresh token is kept, which only the newest sign in can change.
    private let slot = TokenSlot(write: { Keychain.setRefreshToken($0) })
    private var signingInTask: Task<Void, Never>?
    /// Counts each sign in started, so one that's been cancelled or started
    /// again doesn't say it's finished.
    private var signIns = 0
    private var polling: Task<Void, Never>?
    /// What notifications are worked out against.
    private var watch = AlertWatch()
    /// The checks and silences the server listed last, kept for when asking for
    /// them again fails.
    private var lastChecks: [RemoteCheck]?
    private var lastSilences: Silences?
    /// Counts each sign in, sign out and change of settings, so an answer to the
    /// old ones is dropped.
    private var connection = 0
    /// Counts each time the server is asked, and which of those answers was used
    /// last, so an answer overtaken by a later one is dropped. Several can be
    /// asking at once: the regular check, Refresh, and the one after each action.
    private var asks = 0
    private var answered = 0
    let notifier = Notifier()

    struct Account: Equatable {
        /// Their email address.
        let user: String
        let role: String
    }

    static let intervals = [15, 30, 60]
    private static let addressKey = "serverAddress"
    private static let intervalKey = "checkEverySecs"
    private static let userKey = "signedInUser"
    private static let roleKey = "signedInRole"
    static let notifyCriticalKey = "notifyCritical"
    static let notifyWarningsKey = "notifyWarnings"
    static let notifyResolvedKey = "notifyResolved"

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Store.notifyCriticalKey: true,
            Store.notifyWarningsKey: true,
            Store.notifyResolvedKey: true,
        ])
        address = defaults.string(forKey: Store.addressKey) ?? ""
        let saved = defaults.integer(forKey: Store.intervalKey)
        interval = Store.intervals.contains(saved) ? saved : Store.intervals[0]
        notifier.onAcknowledge = { [weak self] alert in
            // Acknowledged from a notification, so a notification says if it didn't
            // work: the menu, where it would otherwise show, may never be opened.
            self?.act({ try await $0.acknowledge(alertID: alert) }) { problem in
                self?.notifier.post(
                    Notice(
                        id: "acknowledge-failed-\(alert)-\(UUID().uuidString)",
                        title: "Couldn't acknowledge the alert",
                        body: problem,
                        acknowledges: nil,
                        path: "/alerts"))
            }
        }
        notifier.onOpen = { [weak self] path in self?.open(path) }
        notifier.start(asking: notifyWhen.any)
        if let refreshToken = Keychain.refreshToken(), let server = try? ServerAddress(address) {
            if let user = defaults.string(forKey: Store.userKey), let role = defaults.string(forKey: Store.roleKey) {
                account = Account(user: user, role: role)
            }
            connect(server) { endpoints, save in
                TokenHolder(refreshToken: refreshToken, endpoints: endpoints, save: save)
            }
        }
    }

    var isSetUp: Bool { client != nil }

    /// Whether the sign in ran out or was revoked, rather than never having been.
    var wasSignedOut: Bool {
        !isSetUp && problem == ClientError.signedOut.localizedDescription
    }

    var headline: String {
        if !isSetUp {
            return wasSignedOut ? "Signed out" : "Not set up"
        }
        return overview?.headline ?? (problem == nil ? "Checking" : "Can't reach the server")
    }

    var notifyWhen: NotifyWhen {
        let defaults = UserDefaults.standard
        return NotifyWhen(
            critical: defaults.bool(forKey: Store.notifyCriticalKey),
            warnings: defaults.bool(forKey: Store.notifyWarningsKey),
            resolved: defaults.bool(forKey: Store.notifyResolvedKey))
    }

    /// How often the server is asked. Applies from the next time it's asked.
    func setInterval(_ interval: Int) {
        self.interval = interval
        UserDefaults.standard.set(interval, forKey: Store.intervalKey)
    }

    /// Opens the server's sign in page in the browser and waits for the person to
    /// approve the app there.
    func signIn(address typed: String) {
        let server: ServerAddress
        do {
            server = try ServerAddress(typed)
        } catch {
            signInProblem = error.localizedDescription
            return
        }
        signingInTask?.cancel()
        signInProblem = nil
        signingIn = true
        signIns += 1
        let attempt = signIns
        signingInTask = Task {
            defer {
                if signIns == attempt {
                    signingIn = false
                }
            }
            do {
                let tokens = try await signInThroughBrowser(
                    server: server, device: Store.computerName,
                    open: { url in await MainActor.run { _ = NSWorkspace.shared.open(url) } })
                guard signIns == attempt else {
                    // Cancelled or started again once the server had signed the app in.
                    do {
                        try await SignInEndpoints(server: server).revoke(unwanted: tokens)
                    } catch {
                        signInProblem = SignInError.cancelledNotRevoked.localizedDescription
                    }
                    return
                }
                Keychain.forgetAPIKey()
                address = typed.trimmingCharacters(in: .whitespacesAndNewlines)
                UserDefaults.standard.set(address, forKey: Store.addressKey)
                signedIn(as: tokens)
                connect(server) { endpoints, save in
                    TokenHolder(tokens: tokens, endpoints: endpoints, save: save)
                }
            } catch {
                guard !isCancellation(error) else { return }
                signInProblem = error.localizedDescription
            }
        }
    }

    func cancelSignIn() {
        signingInTask?.cancel()
        signingInTask = nil
        signIns += 1
        signingIn = false
    }

    /// The Mac's name, as set in System Settings under Sharing.
    private static var computerName: String {
        SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
    }

    /// Signs out here and on the server. If the server can't be told, it's still
    /// signed out here, and the person is told to revoke it on the server.
    func signOut() {
        let tokens = self.tokens
        disconnect()
        signedIn(as: nil)
        // Claimed first, so the sign in being ended can't save a token it's still
        // refreshing, and nothing it does later forgets a newer sign in's.
        let forgot = slot.save(nil, for: slot.claim())
        let keychain = forgot ? "" : " The Keychain wouldn't forget the sign in, so it may be tried again when the app next starts."
        signInProblem = nil
        Task {
            do {
                try await tokens?.signOut()
                if !forgot {
                    signInProblem = "Signed out on the server.\(keychain)"
                }
            } catch {
                signInProblem =
                    "Signed out here, but the server couldn't be told. Revoke it in MaxNines under Settings, then Signed-in apps.\(keychain)"
            }
        }
    }

    private func signedIn(as tokens: Tokens?) {
        account = tokens.map { Account(user: $0.user, role: $0.role) }
        let defaults = UserDefaults.standard
        defaults.set(tokens?.user, forKey: Store.userKey)
        defaults.set(tokens?.role, forKey: Store.roleKey)
    }

    /// Stops asking the server, and forgets what it said.
    private func disconnect() {
        polling?.cancel()
        problem = nil
        overview = nil
        updated = nil
        // Another server's alerts aren't news about this one's.
        watch = AlertWatch()
        saveProblem = nil
        lastChecks = nil
        lastSilences = nil
        connection += 1
        client = nil
        tokens = nil
    }

    /// Starts asking `server`, with tokens from `holder`.
    private func connect(
        _ server: ServerAddress,
        holder: (SignInEndpoints, @escaping @Sendable (Tokens?) -> Bool) -> TokenHolder
    ) {
        disconnect()
        let connected = connection
        let claim = slot.claim()
        // Each refresh token is kept as soon as it comes, and who's signed in kept
        // up to date, unless this sign in has since ended.
        let save: @Sendable (Tokens?) -> Bool = { [weak self, slot] tokens in
            let kept = slot.save(tokens?.refreshToken, for: claim)
            Task { @MainActor in
                guard let self, self.connection == connected else { return }
                self.signedIn(as: tokens)
            }
            return kept
        }
        let tokens = holder(SignInEndpoints(server: server), save)
        self.tokens = tokens
        client = Client(server: server, tokens: tokens)
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = self?.interval ?? Store.intervals[0]
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func refresh() async {
        guard let client, let holder = tokens else { return }
        let asked = connection
        asks += 1
        let ask = asks
        // Whether this is still the newest answer for the settings now in use.
        func current() -> Bool { connection == asked && ask > answered }
        do {
            async let alertsAsked = client.alerts()
            async let hostsAsked = client.hosts()
            // Checks and silences are extras: a server too old to list them, or
            // a sign in not allowed to, still shows its alerts.
            async let checksAsked = outcome { try await client.remoteChecks() }
            async let silencesAsked = outcome { try await client.silences() }
            let (alerts, hosts) = try await (alertsAsked, hostsAsked)
            let (checksGot, silencesGot) = await (checksAsked, silencesAsked)
            let saved = await holder.isSaved
            guard current() else { return }
            answered = ask
            saveProblem = saved
                ? nil
                : "The Keychain won't keep the sign in's newest token, so quitting now would sign the app out. Make sure the login keychain is unlocked."
            let checks = extra(checksGot, before: lastChecks)
            let silences = extra(silencesGot, before: lastSilences)
            lastChecks = checks
            lastSilences = silences
            overview = Overview(alerts: alerts, hosts: hosts, checks: checks, silences: silences?.active ?? [])
            updated = Date()
            problem = nil
            for notice in watch.notices(for: alerts, when: notifyWhen) {
                notifier.post(notice)
            }
        } catch {
            // Cancelled because the settings changed, or overtaken by a later
            // answer, it says nothing about the server now.
            guard current(), !Task.isCancelled, !isCancellation(error) else { return }
            answered = ask
            if error as? ClientError == .signedOut {
                signedOut()
            } else {
                problem = error.localizedDescription
            }
        }
    }

    /// The sign in ran out or was revoked: stop asking, and say to sign in again.
    private func signedOut() {
        disconnect()
        signedIn(as: nil)
        problem = ClientError.signedOut.localizedDescription
    }

    func acknowledge(_ alert: ServerAlert) {
        act { try await $0.acknowledge(alertID: alert.id) }
    }

    func silenceForAnHour(_ alert: ServerAlert) {
        act { try await $0.silence(alert, for: 3600) }
    }

    /// Does something on the server, then asks it again to show the result.
    /// `failed` is told why it didn't work, as well as the menu.
    private func act(_ action: @escaping (Client) async throws -> Void, failed: ((String) -> Void)? = nil) {
        guard let client else {
            failed?("MaxNines isn't set up")
            return
        }
        let asked = connection
        Task {
            do {
                try await action(client)
                actionProblem = nil
            } catch {
                actionProblem = error.localizedDescription
                failed?(error.localizedDescription)
                if error as? ClientError == .signedOut, connection == asked {
                    signedOut()
                    return
                }
            }
            await refresh()
        }
    }

    /// Opens a page of the web interface in the browser.
    func open(_ path: String) {
        if let client {
            NSWorkspace.shared.open(client.page(path))
        }
    }
}

/// How `work` went.
private func outcome<Value>(_ work: () async throws -> Value) async -> Result<Value, Error> {
    do {
        return .success(try await work())
    } catch {
        return .failure(error)
    }
}

private func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

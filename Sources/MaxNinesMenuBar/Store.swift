import AppKit
import MaxNinesKit
import SwiftUI

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

    private var client: Client?
    private var polling: Task<Void, Never>?
    /// The alerts the server listed last time, which notifications are worked
    /// out against. Nothing until the first answer, so what was already firing
    /// isn't announced.
    private var lastAlerts: Alerts?
    /// Counts each change of settings, so an answer to the old ones is dropped.
    private var connection = 0
    let notifier = Notifier()

    static let intervals = [15, 30, 60]
    private static let addressKey = "serverAddress"
    private static let intervalKey = "checkEverySecs"
    static let notifyCriticalKey = "notifyCritical"
    static let notifyWarningsKey = "notifyWarnings"
    static let notifyResolvedKey = "notifyResolved"

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Store.notifyCriticalKey: true,
            Store.notifyWarningsKey: false,
            Store.notifyResolvedKey: true,
        ])
        address = defaults.string(forKey: Store.addressKey) ?? ""
        let saved = defaults.integer(forKey: Store.intervalKey)
        interval = Store.intervals.contains(saved) ? saved : Store.intervals[0]
        notifier.onAcknowledge = { [weak self] alert in
            self?.act { try await $0.acknowledge(alertID: alert) }
        }
        notifier.onOpen = { [weak self] path in self?.open(path) }
        notifier.start(asking: notifyWhen.any)
        connect(apiKey: Keychain.apiKey() ?? "")
    }

    var isSetUp: Bool { client != nil }
    var hasAPIKey: Bool { !(Keychain.apiKey() ?? "").isEmpty }
    var sendsKeyInTheClear: Bool { client?.sendsKeyInTheClear ?? false }

    var headline: String {
        if !isSetUp {
            return "Not set up"
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

    /// Saves the settings and starts again with them. An empty key keeps the one
    /// that's saved.
    func save(address: String, apiKey: String, interval: Int) {
        let defaults = UserDefaults.standard
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.interval = interval
        defaults.set(self.address, forKey: Store.addressKey)
        defaults.set(interval, forKey: Store.intervalKey)
        if !apiKey.isEmpty {
            Keychain.setAPIKey(apiKey)
        }
        overview = nil
        updated = nil
        connect(apiKey: Keychain.apiKey() ?? "")
    }

    private func connect(apiKey: String) {
        polling?.cancel()
        problem = nil
        // Another server's alerts aren't news about this one's.
        lastAlerts = nil
        connection += 1
        client = apiKey.isEmpty ? nil : try? Client(address: address, apiKey: apiKey)
        guard client != nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let seconds = self?.interval ?? Store.intervals[0]
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func refresh() async {
        guard let client else { return }
        let asked = connection
        do {
            async let alertsAsked = client.alerts()
            async let hostsAsked = client.hosts()
            // Checks and silences are extras: a server too old to list them, or
            // a key not allowed to, still shows its alerts.
            async let checksAsked = try? client.remoteChecks()
            async let silencesAsked = try? client.silences()
            let (alerts, hosts) = try await (alertsAsked, hostsAsked)
            let (checks, silences) = await (checksAsked, silencesAsked)
            // The settings changed while it was asking.
            guard connection == asked else { return }
            overview = Overview(alerts: alerts, hosts: hosts, checks: checks, silences: silences?.active ?? [])
            updated = Date()
            problem = nil
            if let lastAlerts {
                for notice in notices(from: lastAlerts, to: alerts, when: notifyWhen) {
                    notifier.post(notice)
                }
            }
            lastAlerts = alerts
        } catch is CancellationError {
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Tries settings without saving them, and says how it went.
    func test(address: String, apiKey: String) async -> Result<String, ClientError> {
        let key = apiKey.isEmpty ? Keychain.apiKey() ?? "" : apiKey
        do {
            let client = try Client(address: address, apiKey: key)
            let hosts = try await client.hosts().filter(\.isCounted)
            return .success("Connected. It has \(hosts.count) \(hosts.count == 1 ? "host" : "hosts").")
        } catch let error as ClientError {
            return .failure(error)
        } catch {
            return .failure(.notMaxNines)
        }
    }

    func acknowledge(_ alert: ServerAlert) {
        act { try await $0.acknowledge(alertID: alert.id) }
    }

    func silenceForAnHour(_ alert: ServerAlert) {
        act { try await $0.silence(alert, for: 3600) }
    }

    private func act(_ action: @escaping (Client) async throws -> Void) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                actionProblem = nil
            } catch {
                actionProblem = error.localizedDescription
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

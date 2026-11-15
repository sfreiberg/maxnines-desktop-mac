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

    static let intervals = [15, 30, 60]
    private static let addressKey = "serverAddress"
    private static let intervalKey = "checkEverySecs"

    init() {
        let defaults = UserDefaults.standard
        address = defaults.string(forKey: Store.addressKey) ?? ""
        let saved = defaults.integer(forKey: Store.intervalKey)
        interval = Store.intervals.contains(saved) ? saved : Store.intervals[0]
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
        do {
            async let alerts = client.alerts()
            async let hosts = client.hosts()
            overview = try await Overview(alerts: alerts, hosts: hosts)
            updated = Date()
            problem = nil
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
        act { try await $0.acknowledge(alert) }
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

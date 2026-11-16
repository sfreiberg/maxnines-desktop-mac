import MaxNinesKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var address = ""
    @State private var apiKey = ""
    @State private var interval = Store.intervals[0]
    @State private var result: Result<String, ClientError>?
    @State private var testing = false

    var body: some View {
        Form {
            Section("Server") {
                TextField("Address", text: $address, prompt: Text("https://monitor.example.com"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                SecureField(
                    "API key", text: $apiKey,
                    prompt: Text(store.hasAPIKey ? "Leave empty to keep the one that's saved" : "From Settings in MaxNines"))
                Text(
                    "Kept in your Keychain. A viewer key shows alerts. A responder key can also acknowledge and silence them."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                if let addressProblem {
                    Text(addressProblem).font(.callout).foregroundStyle(.red)
                } else if sendsKeyInTheClear {
                    Text("Over plain http the key crosses the network unencrypted, so only use it on a network you trust.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    Button("Test connection") { test() }
                        .disabled(testing || !canUse)
                    if testing {
                        ProgressView().controlSize(.small)
                    }
                    switch result {
                    case .success(let message): Label(message, systemImage: "checkmark").foregroundStyle(.green)
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "xmark").foregroundStyle(.red)
                    case nil: EmptyView()
                    }
                }
                Picker("Check every", selection: $interval) {
                    ForEach(Store.intervals, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) seconds" : "1 minute").tag(seconds)
                    }
                }
                HStack {
                    Spacer()
                    Button("Save") {
                        store.save(address: address, apiKey: apiKey, interval: interval)
                        apiKey = ""
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canUse)
                }
            }
            NotificationSettings(notifier: store.notifier)
            OpenAtLogin()
            Section {
                Text(Build.describe())
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            address = store.address
            interval = store.interval
        }
    }

    /// What's typed, read the way it will be used, or nil while there's nothing.
    private var typed: Result<Client, Error>? {
        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : Result { try Client(address: address, apiKey: "") }
    }

    private var addressProblem: String? {
        if case .failure(let error) = typed { error.localizedDescription } else { nil }
    }

    private var sendsKeyInTheClear: Bool {
        if case .success(let client) = typed { client.sendsKeyInTheClear } else { false }
    }

    /// Whether there's an address that works and a key, typed or saved.
    private var canUse: Bool {
        guard case .success = typed else { return false }
        return !apiKey.isEmpty || store.hasAPIKey
    }

    private func test() {
        testing = true
        result = nil
        Task {
            result = await store.test(address: address, apiKey: apiKey)
            testing = false
        }
    }
}

/// When to be told about alerts. These apply as soon as they're changed.
private struct NotificationSettings: View {
    @ObservedObject var notifier: Notifier
    @AppStorage(Store.notifyCriticalKey) private var critical = true
    @AppStorage(Store.notifyWarningsKey) private var warnings = false
    @AppStorage(Store.notifyResolvedKey) private var resolved = true

    var body: some View {
        Section("Notifications") {
            Toggle("When a critical alert starts", isOn: $critical)
            Toggle("When a warning starts", isOn: $warnings)
            Toggle("When an alert resolves", isOn: $resolved)
            Text("Silenced alerts never send one.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if notifier.allowed == false && (critical || warnings || resolved) {
                HStack(spacing: 12) {
                    Text("macOS has notifications from MaxNines turned off.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Button("Notification Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
        .onChange(of: critical || warnings || resolved) { _, wanted in
            if wanted {
                notifier.ask()
            }
        }
    }
}

/// Starting with the Mac, through macOS's own list of login items.
private struct OpenAtLogin: View {
    @State private var status = SMAppService.mainApp.status
    @State private var problem: String?

    var body: some View {
        Section {
            Toggle("Open at login", isOn: Binding(get: { status == .enabled }, set: change))
            if status == .requiresApproval {
                HStack(spacing: 12) {
                    Text("macOS needs you to allow it in Login Items.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            if let problem {
                Text(problem).font(.callout).foregroundStyle(.red)
            }
        }
        // It can be changed in System Settings while this window is closed.
        .onAppear { status = SMAppService.mainApp.status }
    }

    private func change(_ wanted: Bool) {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = nil
        } catch {
            problem = "macOS wouldn't change it: \(error.localizedDescription)"
        }
        status = SMAppService.mainApp.status
    }
}

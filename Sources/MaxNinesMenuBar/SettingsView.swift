import MaxNinesKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var address = ""

    var body: some View {
        Form {
            Section("Server") {
                if store.isSetUp {
                    signedIn(store.account)
                } else {
                    signIn
                }
                if let problem = store.signInProblem {
                    Text(problem).font(.callout).foregroundStyle(.red)
                }
                Picker("Check every", selection: Binding(get: { store.interval }, set: store.setInterval)) {
                    ForEach(Store.intervals, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) seconds" : "1 minute").tag(seconds)
                    }
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
        }
    }

    private func signedIn(_ account: Store.Account?) -> some View {
        Group {
            LabeledContent("Address", value: store.address)
            HStack(spacing: 12) {
                Text(account.map { "Signed in as \($0.user) (\($0.role))" } ?? "Signed in")
                Spacer(minLength: 0)
                Button("Sign out") { store.signOut() }
            }
            if account?.role == "viewer" {
                Text("A viewer can't acknowledge or silence alerts. To do that, sign out, then sign in again and choose responder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if (try? ServerAddress(store.address))?.isInTheClear == true {
                inTheClear
            }
        }
    }

    private var signIn: some View {
        Group {
            TextField("Address", text: $address, prompt: Text("https://monitor.example.com"))
                .textContentType(.URL)
                .autocorrectionDisabled()
                .disabled(store.signingIn)
            if store.wasSignedOut {
                Text("The app's sign in ran out or was revoked. Sign in again to see alerts.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            if let addressProblem {
                Text(addressProblem).font(.callout).foregroundStyle(.red)
            } else if typed?.isInTheClear == true {
                inTheClear
            }
            HStack(spacing: 12) {
                if store.signingIn {
                    ProgressView().controlSize(.small)
                    Text("Waiting for you to sign in in the browser")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Cancel") { store.cancelSignIn() }
                } else {
                    Text("Your browser opens MaxNines for you to allow the app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Sign in with browser") { store.signIn(address: address) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(typed == nil)
                }
            }
        }
    }

    private var inTheClear: some View {
        Text("Over plain http the sign in crosses the network unencrypted, so only use it on a network you trust.")
            .font(.callout)
            .foregroundStyle(.orange)
    }

    /// What's typed, read the way it will be used, or nil while there's nothing.
    private var read: Result<ServerAddress, Error>? {
        address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : Result { try ServerAddress(address) }
    }

    /// The server typed, if it's one that works.
    private var typed: ServerAddress? {
        if case .success(let server) = read { server } else { nil }
    }

    private var addressProblem: String? {
        if case .failure(let error) = read { error.localizedDescription } else { nil }
    }
}

/// When to be told about alerts. These apply as soon as they're changed.
private struct NotificationSettings: View {
    @ObservedObject var notifier: Notifier
    @AppStorage(Store.notifyCriticalKey) private var critical = true
    @AppStorage(Store.notifyWarningsKey) private var warnings = true
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

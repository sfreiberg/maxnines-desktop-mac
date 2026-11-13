import MaxNinesKit
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
                if address.lowercased().hasPrefix("http://") {
                    Text("Over plain http the key crosses the network unencrypted, so only use it on a network you trust.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 12) {
                    Button("Test connection") { test() }
                        .disabled(testing || address.isEmpty || (apiKey.isEmpty && !store.hasAPIKey))
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
            }
            Section {
                Picker("Check every", selection: $interval) {
                    ForEach(Store.intervals, id: \.self) { seconds in
                        Text(seconds < 60 ? "\(seconds) seconds" : "1 minute").tag(seconds)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Save") {
                    store.save(address: address, apiKey: apiKey, interval: interval)
                    apiKey = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(address.isEmpty || (apiKey.isEmpty && !store.hasAPIKey))
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

    private func test() {
        testing = true
        result = nil
        Task {
            result = await store.test(address: address, apiKey: apiKey)
            testing = false
        }
    }
}

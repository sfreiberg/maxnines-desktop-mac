import MaxNinesKit
import SwiftUI

@main
struct MaxNinesMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// It lives in the menu bar, with no Dock icon or main window.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The icon says the worst thing happening: filled with a count when something
/// is critical, a count alone for warnings, and a question mark when the server
/// can't be asked, so that quiet isn't mistaken for fine.
struct MenuBarLabel: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: store.overview?.worst == .critical ? "9.square.fill" : "9.square")
            if let mark {
                Text(mark)
            }
        }
        .accessibilityLabel("MaxNines, \(store.headline)")
    }

    private var mark: String? {
        if store.problem != nil || store.overview == nil {
            return "?"
        }
        let firing = store.overview?.firing.count ?? 0
        return firing > 0 ? "\(firing)" : nil
    }
}

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
            MenuBarLabel(store: store, delegate: delegate)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opens Settings, once the menu bar icon is there to say how.
    @MainActor var openSettings: (() -> Void)?

    /// It lives in the menu bar, with no Dock icon or main window.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// Opened again while it's running, as from Applications or Spotlight. Its menu
    /// bar icon may be out of sight, as behind the camera housing, so Settings opens
    /// to show it's running, rather than nothing happening.
    @MainActor func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        openSettings?()
        return false
    }
}

/// The icon says the worst thing happening, as `IconState` describes.
struct MenuBarLabel: View {
    @ObservedObject var store: Store
    let delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: menuBarImage(IconState(overview: store.overview, problem: store.problem)))
            .accessibilityLabel("MaxNines, \(store.headline)")
            .onAppear { delegate.openSettings = { openSettings() } }
    }
}

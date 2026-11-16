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

/// The icon says the worst thing happening, as `IconState` describes.
struct MenuBarLabel: View {
    @ObservedObject var store: Store

    var body: some View {
        Image(nsImage: menuBarImage(IconState(overview: store.overview, problem: store.problem)))
            .accessibilityLabel("MaxNines, \(store.headline)")
    }
}

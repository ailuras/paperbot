import SwiftUI
import AppKit

/// Bridges SwiftUI's `openWindow` action to AppKit code (the menu bar
/// controller), so "Open VellumX" can recreate the main window even after it
/// was closed. The App captures the action on appear.
@MainActor
final class MainWindowOpener {
    static let shared = MainWindowOpener()
    var openAction: (() -> Void)?

    func open() {
        // Prefer re-fronting an existing main window (a titled standard window,
        // not the Settings or popover window) to avoid spawning duplicates.
        if let window = NSApp.windows.first(where: {
            $0.canBecomeMain && $0.styleMask.contains(.titled) && $0.frame.width >= 900
        }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openAction?()   // WindowGroup window was closed — recreate it
        }
    }
}

@main
struct VellumXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = PaperStore.shared
    @StateObject private var settings = AppSettings.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .frame(minWidth: 900, minHeight: 550)
                .onAppear {
                    MainWindowOpener.shared.openAction = { openWindow(id: "main") }
                }
        }

        Settings {
            SettingsRootView()
                .environmentObject(settings)
        }
    }
}

/// Hosts the AppKit-based menu bar status item (see MenuBarController for why
/// we avoid SwiftUI's MenuBarExtra with a custom image).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(store: .shared, settings: .shared)
    }
}

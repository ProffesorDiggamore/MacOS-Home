import SwiftUI
import AppKit

@main
struct HomeWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Every window is managed by AppController. This empty scene just satisfies SwiftUI.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WidgetStore.shared.saveNow()
    }

    /// Opening the app again (e.g. from Finder or Spotlight) shows the gallery.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppController.shared.showSettings(pane: .gallery)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

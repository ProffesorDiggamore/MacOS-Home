import SwiftUI
import AppKit

@main
struct HomeWidgetsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Every window is managed by AppController. This scene only provides the menu bar commands.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Home Widgets") {
                    AppController.shared.showSettings(pane: .about)
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppController.shared.showSettings(pane: .appearance)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Widget Gallery") {
                    AppController.shared.showSettings(pane: .gallery)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("My Widgets") {
                    AppController.shared.showSettings(pane: .myWidgets)
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("Accounts") {
                    AppController.shared.showSettings(pane: .accounts)
                }
            }
            CommandMenu("Widgets") {
                Button("Hide or Show Widgets") {
                    AppearanceSettings.shared.hidden.toggle()
                }
                .keyboardShortcut("h", modifiers: [.command, .option])
                Button("Arrange Widgets") {
                    AppController.shared.arrangeWidgets()
                }
                Button("Lock or Unlock Positions") {
                    AppearanceSettings.shared.locked.toggle()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAsLoginItem = false
    private var terminationSource: DispatchSourceSignal?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 'oapp' event with the 'lgit' property means macOS opened us as a login item.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let openApplication: AEEventID = 0x6F61_7070 // 'oapp'
        let propertyData: AEKeyword = 0x7072_6474 // 'prdt'
        let loginItem: OSType = 0x6C67_6974 // 'lgit'
        launchedAsLoginItem = event?.eventID == openApplication
            && event?.paramDescriptor(forKeyword: propertyData)?.enumCodeValue == loginItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let folder = UserDefaults.standard.string(forKey: "HWSnapshots") {
            return Snapshots.run(to: folder)
        }
        if let folder = UserDefaults.standard.string(forKey: "HWWallpapers") {
            return Snapshots.wallpapers(to: folder)
        }
        #endif
        // `-HWNoWindow YES` (used by the screenshot test) starts with just the widgets.
        let suppressWindow = UserDefaults.standard.bool(forKey: "HWNoWindow")
        AppController.shared.start(showWindow: !launchedAsLoginItem && !suppressWindow)

        // `make install` stops the old copy with SIGTERM; save widget positions before exiting.
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            WidgetStore.shared.saveNow()
            exit(0)
        }
        source.resume()
        terminationSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        WidgetStore.shared.saveNow()
    }

    /// Clicking the Dock icon (or opening the app again from Finder/Spotlight) shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppController.shared.showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        AppController.shared.dockMenu()
    }
}

import AppKit
import SwiftUI
import Combine
import ServiceManagement

/// Coordinates the menu bar item, widget windows, and the settings window.
@MainActor
final class AppController: NSObject, NSMenuDelegate {
    static let shared = AppController()

    private let store = WidgetStore.shared
    private let appearance = AppearanceSettings.shared
    private var panels: [UUID: WidgetPanelController] = [:]
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Startup

    func start() {
        let hadSavedWidgets = store.load()
        if !hadSavedWidgets {
            installDefaultWidgets()
        }
        setupStatusItem()
        syncPanels(store.widgets)

        store.$widgets
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] widgets in self?.syncPanels(widgets) }
            .store(in: &cancellables)

        appearance.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applyWindowSettings() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &cancellables)

        if !hadSavedWidgets {
            showSettings(pane: .gallery)
        }
    }

    private func installDefaultWidgets() {
        let defaults: [(WidgetKind, WidgetSize)] = [
            (.clock, .small),
            (.calendar, .small),
            (.claude, .medium),
            (.systemStats, .medium),
            (.appShortcuts, .medium),
            (.weather, .small),
            (.battery, .small),
        ]
        for (kind, size) in defaults {
            addWidget(kind, size: size)
        }
    }

    // MARK: Widgets

    @discardableResult
    func addWidget(_ kind: WidgetKind, size: WidgetSize? = nil) -> WidgetModel {
        let chosen = size ?? kind.defaultSize
        let screen = NSScreen.main ?? NSScreen.screens.first
        let bounds = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let occupied = store.widgets.map(\.frame)
        let topLeft = Placement.freeTopLeft(for: chosen.dimensions, in: bounds, occupied: occupied)
        let model = WidgetModel(kind: kind, size: chosen, topLeft: topLeft)
        applyInitialConfig(to: model)
        store.add(model)
        if appearance.hidden {
            appearance.hidden = false
        }
        return model
    }

    /// Saves defaults that depend on this Mac (installed apps, next New Year…) so they stay stable.
    private func applyInitialConfig(to model: WidgetModel) {
        switch model.kind {
        case .appShortcuts:
            model.config[AppShortcutKeys.apps] = AppShortcutDefaults.paths()
        case .countdown:
            model.config[CountdownKeys.target] = Countdown.nextNewYear()
        default:
            break
        }
    }

    func removeWidget(_ id: UUID) {
        // Defer so a context menu inside the widget can finish closing first.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.store.remove(id)
                if SettingsState.shared.selectedWidget == id {
                    SettingsState.shared.selectedWidget = nil
                }
            }
        }
    }

    func widgetFrames(excluding id: UUID) -> [CGRect] {
        store.widgets.filter { $0.id != id }.map(\.frame)
    }

    func arrangeWidgets() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let bounds = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        var placed: [CGRect] = []
        for model in store.widgets {
            let size = model.size.dimensions
            let topLeft = Placement.freeTopLeft(for: size, in: bounds, occupied: placed)
            let rect = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
            placed.append(rect)
            panels[model.id]?.move(to: rect, animated: true)
        }
    }

    func resetWidgets() {
        store.removeAll()
        installDefaultWidgets()
    }

    private func syncPanels(_ widgets: [WidgetModel]) {
        let ids = Set(widgets.map(\.id))
        for (id, controller) in panels where !ids.contains(id) {
            controller.close()
            panels[id] = nil
        }
        for model in widgets where panels[model.id] == nil {
            let controller = WidgetPanelController(model: model)
            panels[model.id] = controller
            controller.show()
        }
    }

    private func applyWindowSettings() {
        for controller in panels.values {
            controller.applySettings()
        }
    }

    private func screensChanged() {
        for model in store.widgets {
            panels[model.id]?.ensureVisible { [weak self] in
                guard let self else { return .zero }
                let screen = NSScreen.main ?? NSScreen.screens.first
                let bounds = screen?.visibleFrame ?? .zero
                return Placement.freeTopLeft(for: model.size.dimensions, in: bounds,
                                             occupied: self.widgetFrames(excluding: model.id))
            }
        }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Home Widgets")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Home Widgets"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let add = NSMenuItem(title: "Add Widget", action: nil, keyEquivalent: "")
        let addMenu = NSMenu()
        for category in WidgetCategory.allCases {
            let header = NSMenuItem(title: category.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            addMenu.addItem(header)
            for kind in WidgetKind.allCases where kind.category == category {
                let entry = menuItem(kind.title, #selector(quickAdd(_:)))
                entry.representedObject = kind.rawValue
                entry.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                entry.indentationLevel = 1
                addMenu.addItem(entry)
            }
        }
        add.submenu = addMenu
        menu.addItem(add)
        menu.addItem(menuItem("Widget Gallery…", #selector(openGallery), key: "n"))
        menu.addItem(menuItem("Edit Widgets…", #selector(openMyWidgets), key: "e"))
        menu.addItem(.separator())

        let hide = menuItem("Hide Widgets", #selector(toggleHidden), key: "h")
        hide.state = appearance.hidden ? .on : .off
        menu.addItem(hide)
        let lock = menuItem("Lock Widget Positions", #selector(toggleLock))
        lock.state = appearance.locked ? .on : .off
        menu.addItem(lock)
        let floating = menuItem("Keep Widgets Above Windows", #selector(toggleFloating))
        floating.state = appearance.layer == .floating ? .on : .off
        menu.addItem(floating)
        menu.addItem(menuItem("Arrange Widgets", #selector(arrangeFromMenu)))
        menu.addItem(.separator())

        let login = menuItem("Open at Login", #selector(toggleLaunchAtLogin))
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(menuItem("Settings…", #selector(openAppearance), key: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Home Widgets", #selector(quit), key: "q"))
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func quickAdd(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = WidgetKind(rawValue: raw) else { return }
        addWidget(kind)
    }

    @objc private func openGallery() { showSettings(pane: .gallery) }
    @objc private func openMyWidgets() { showSettings(pane: .myWidgets) }
    @objc private func openAppearance() { showSettings(pane: .appearance) }
    @objc private func toggleHidden() { appearance.hidden.toggle() }
    @objc private func toggleLock() { appearance.locked.toggle() }
    @objc private func toggleFloating() { appearance.layer = appearance.layer == .floating ? .desktop : .floating }
    @objc private func arrangeFromMenu() { arrangeWidgets() }
    @objc private func toggleLaunchAtLogin() { LaunchAtLogin.toggle() }
    @objc private func quit() {
        store.saveNow()
        NSApp.terminate(nil)
    }

    // MARK: Settings window

    func showSettings(pane: SettingsPane? = nil, widget: UUID? = nil) {
        let state = SettingsState.shared
        if let widget {
            state.pane = .myWidgets
            state.selectedWidget = widget
        } else if let pane {
            state.pane = pane
        }

        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsRootView())
            controller.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: controller)
            window.title = "Home Widgets"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.toolbarStyle = .unified
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 920, height: 640))
            window.center()
            window.setFrameAutosaveName("HomeWidgetsSettings")
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isSupported: Bool { Shell.isBundled }

    @MainActor
    static func toggle() {
        set(!isEnabled)
    }

    @MainActor
    static func set(_ enabled: Bool) {
        guard isSupported else {
            showAlert("Open at Login works once Home Widgets is installed as an app (run `make install`).")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            showAlert("Couldn't change the login item: \(error.localizedDescription)\n\nYou can also add Home Widgets in System Settings › General › Login Items.")
        }
    }

    @MainActor
    private static func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Open at Login"
        alert.informativeText = message
        NSApp.activate()
        _ = alert.runModal()
    }
}

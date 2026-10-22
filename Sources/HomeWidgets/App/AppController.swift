import AppKit
import SwiftUI
import Combine
import ServiceManagement

/// Coordinates the menu bar item, widget windows, and the settings window.
@MainActor
final class AppController: NSObject, NSMenuDelegate {
    static let shared = AppController()

    let store = WidgetStore.shared
    private let appearance = AppearanceSettings.shared
    private(set) var panels: [UUID: WidgetPanelController] = [:]
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Startup

    func start(showWindow: Bool) {
        let hadSavedWidgets = store.load()
        if !hadSavedWidgets {
            installDefaultWidgets()
        }
        applyAppPresence()
        DesktopGrid.verticalOffset = CGFloat(appearance.gridOffset)
        DesktopGrid.rowLimit = appearance.gridRows
        tidyOntoGrid()
        syncPanels(store.widgets)

        // Moving the grid (Settings › General › Grid) slides every widget along with it.
        appearance.$gridOffset.combineLatest(appearance.$gridRows)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] offset, rows in self?.moveGrid(offset: CGFloat(offset), rows: rows) }
            .store(in: &cancellables)

        store.$widgets
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] widgets in self?.syncPanels(widgets) }
            .store(in: &cancellables)

        appearance.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyWindowSettings()
                self?.applyAppPresence()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screensChanged() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.panels.values.forEach { $0.spaceChanged() } }
            .store(in: &cancellables)

        if showWindow || !hadSavedWidgets {
            showSettings(pane: hadSavedWidgets ? nil : .gallery)
        }
    }

    /// Dock icon and menu bar icon, based on settings. At least one way back into the app stays available:
    /// opening the app from Finder or Spotlight always shows the window.
    private func applyAppPresence() {
        let policy: NSApplication.ActivationPolicy = appearance.showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
            if policy == .regular, settingsWindow?.isVisible == true {
                NSApp.activate()
            }
        }
        if appearance.showMenuBarIcon {
            if statusItem == nil { setupStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
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

    /// Adds a widget in the first free slot. If the chosen size doesn't fit anywhere it
    /// tries the widget's smaller sizes; if nothing fits, it says the desktop is full
    /// and adds nothing, instead of stacking the new widget on top of another.
    @discardableResult
    func addWidget(_ kind: WidgetKind, size: WidgetSize? = nil) -> WidgetModel? {
        let chosen = size ?? kind.defaultSize
        let area = { (s: WidgetSize) in s.cells.columns * s.cells.rows }
        let fallbacks = kind.sizes.filter { area($0) < area(chosen) }.sorted { area($0) > area($1) }
        let screen = NSScreen.main ?? NSScreen.screens.first
        let grid = DesktopGrid(bounds: DesktopGrid.area(of: screen))
        let occupied = store.widgets.map(\.frame)
        var found: (WidgetSize, CGRect)?
        for candidate in [chosen] + fallbacks {
            let rect = grid.firstFree(size: candidate, occupied: occupied).map { grid.rect(at: $0, size: candidate) }
                ?? DesktopGrid.place(grid.rect(at: .init(column: 0, row: 0), size: candidate), size: candidate, occupied: occupied)
            if let rect {
                found = (candidate, rect)
                break
            }
        }
        guard let (fitted, rect) = found else {
            Self.showNoRoom("There's no free space for \(kind.title).",
                            detail: "Remove a widget or make one smaller, then add it again.")
            return nil
        }
        let model = WidgetModel(kind: kind, size: fitted, topLeft: CGPoint(x: rect.minX, y: rect.maxY))
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

    /// Tells you a widget couldn't be placed because the grid is full.
    static func showNoRoom(_ message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
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

    /// Packs every widget into the grid from the top-left, biggest first so nothing gets stranded.
    func arrangeWidgets() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let grid = DesktopGrid(bounds: DesktopGrid.area(of: screen))
        var placed: [CGRect] = []
        let ordered = store.widgets.sorted {
            let a = $0.size.cells, b = $1.size.cells
            return a.columns * a.rows > b.columns * b.rows
        }
        for model in ordered {
            let rect = grid.firstFree(size: model.size, occupied: placed).map { grid.rect(at: $0, size: model.size) }
                ?? DesktopGrid.place(model.frame, size: model.size, occupied: placed)
                ?? model.frame
            placed.append(rect)
            panels[model.id]?.move(to: rect, animated: true)
        }
    }

    // MARK: Drag reflow

    /// Where every other widget was when the drag began; each step is planned from these,
    /// so widgets that were pushed aside slide back once the dragged one moves on.
    private var dragOriginals: [(id: UUID, size: WidgetSize, rect: CGRect)] = []
    private var dragPlan: [UUID: CGRect] = [:]

    /// Where the dragged widget started, so it can go back there when there's no room.
    private var dragHome: CGRect?

    func beginDrag(_ id: UUID) {
        dragOriginals = store.widgets.filter { $0.id != id }.map { ($0.id, $0.size, $0.frame) }
        dragHome = store.widgets.first { $0.id == id }?.frame
        dragPlan = [:]
    }

    /// The slot the dragged widget takes if dropped now. Widgets in that slot slide to the
    /// nearest free spot, like app icons on an iPhone; if there's no room for them, the
    /// dragged widget takes the nearest free slot instead and nothing moves.
    func reflow(dragging frame: CGRect, size: WidgetSize) -> CGRect {
        let grid = DesktopGrid.forRect(frame)
        let target = grid.rect(at: grid.nearestCell(to: frame, size: size), size: size)
        var plan: [UUID: CGRect] = [:]
        var occupied = [target]
        var bumped: [(id: UUID, size: WidgetSize, rect: CGRect)] = []
        for other in dragOriginals {
            if other.rect.insetBy(dx: 2, dy: 2).intersects(target) {
                bumped.append(other)
            } else {
                occupied.append(other.rect)
            }
        }
        bumped.sort { $0.rect.maxY != $1.rect.maxY ? $0.rect.maxY > $1.rect.maxY : $0.rect.minX < $1.rect.minX }
        for other in bumped {
            let otherGrid = DesktopGrid.forRect(other.rect)
            guard let cell = otherGrid.nearestFree(to: otherGrid.nearestCell(to: other.rect, size: other.size),
                                                   size: other.size, occupied: occupied) else {
                showPlan([:])
                return DesktopGrid.place(frame, size: size, occupied: dragOriginals.map(\.rect))
                    ?? dragHome ?? target
            }
            let moved = otherGrid.rect(at: cell, size: other.size)
            plan[other.id] = moved
            occupied.append(moved)
        }
        showPlan(plan)
        return target
    }

    /// Slides pushed-aside widgets to their planned spots (and the rest back home) without saving yet.
    private func showPlan(_ plan: [UUID: CGRect]) {
        for other in dragOriginals {
            let rect = plan[other.id] ?? other.rect
            if (dragPlan[other.id] ?? other.rect) != rect {
                panels[other.id]?.preview(at: rect)
            }
        }
        dragPlan = plan
    }

    /// Saves where the pushed-aside widgets ended up.
    func endDrag() {
        for (id, rect) in dragPlan {
            panels[id]?.move(to: rect, animated: false)
        }
        dragOriginals = []
        dragPlan = [:]
        dragHome = nil
    }

    /// Moves saved widgets onto the grid once at launch, pulling apart any that overlap.
    private func tidyOntoGrid() {
        var placed: [CGRect] = []
        for model in store.widgets {
            // A widget with nowhere to go (the desktop was over-full) snaps to its nearest slot;
            // remove or shrink something and it can be dragged into the freed space.
            let grid = DesktopGrid.forRect(model.frame)
            let rect = DesktopGrid.place(model.frame, size: model.size, occupied: placed)
                ?? grid.rect(at: grid.nearestCell(to: model.frame, size: model.size), size: model.size)
            placed.append(rect)
            if rect.origin != model.frame.origin {
                model.topLeft = CGPoint(x: rect.minX, y: rect.maxY)
            }
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
            panels[model.id]?.ensureVisible(occupied: widgetFrames(excluding: model.id))
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
                entry.image = kind.isSlate ? SlateLogo.menuImage : NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
                entry.indentationLevel = 1
                addMenu.addItem(entry)
            }
        }
        add.submenu = addMenu
        menu.addItem(add)
        menu.addItem(menuItem("Widget Gallery…", #selector(openGallery), key: "n"))
        menu.addItem(menuItem("Edit Widgets…", #selector(openMyWidgets), key: "e"))
        menu.addItem(menuItem("Wallpapers…", #selector(openWallpapers)))
        menu.addItem(menuItem("Accounts…", #selector(openAccounts)))
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

    /// Right-click menu on the Dock icon.
    func dockMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuItem("Widget Gallery", #selector(openGallery)))
        menu.addItem(menuItem("My Widgets", #selector(openMyWidgets)))
        menu.addItem(.separator())
        let hide = menuItem("Hide Widgets", #selector(toggleHidden))
        hide.state = appearance.hidden ? .on : .off
        menu.addItem(hide)
        menu.addItem(menuItem("Arrange Widgets", #selector(arrangeFromMenu)))
        return menu
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
    @objc private func openWallpapers() { showSettings(pane: .wallpapers) }
    @objc private func openAppearance() { showSettings(pane: .appearance) }
    @objc private func openAccounts() { showSettings(pane: .accounts) }
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

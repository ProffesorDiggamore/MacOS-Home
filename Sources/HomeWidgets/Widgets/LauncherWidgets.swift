import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - App shortcuts

enum AppShortcutKeys {
    static let apps = ConfigKey<[String]>("apps", [])
    static let showLabels = ConfigKey("showLabels", true)
}

enum AppShortcutDefaults {
    static let candidates = [
        "/Applications/Safari.app",
        "/System/Applications/Messages.app",
        "/System/Applications/Mail.app",
        "/System/Applications/Music.app",
        "/System/Applications/Notes.app",
        "/System/Applications/Calendar.app",
        "/Applications/Claude.app",
        "/System/Applications/Utilities/Terminal.app",
        "/Applications/Visual Studio Code.app",
        "/Applications/Xcode.app",
        "/System/Applications/Photos.app",
        "/System/Applications/App Store.app",
        "/System/Applications/System Settings.app",
        "/System/Applications/Reminders.app",
        "/System/Applications/FaceTime.app",
        "/System/Applications/Maps.app",
    ]

    static func paths(limit: Int = 8) -> [String] {
        Array(candidates.filter { FileManager.default.fileExists(atPath: $0) }.prefix(limit))
    }

    static func displayName(_ path: String) -> String {
        FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
    }
}

struct AppShortcutsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var running = RunningApps.shared
    @State private var dropTargeted = false

    private var showLabels: Bool { model[AppShortcutKeys.showLabels] }
    private var area: CGSize {
        let dims = model.size.dimensions
        return CGSize(width: dims.width - 24, height: dims.height - 24)
    }

    private var apps: [String] {
        let stored = model[AppShortcutKeys.apps]
        return stored.isEmpty ? AppShortcutDefaults.paths() : stored
    }

    var body: some View {
        let label: CGFloat = showLabels ? 22 : 10
        let visible = Array(apps.prefix(TileLayout.capacity(in: area, label: label, minTile: 44)))
        // Icons grow to fill the widget when there are only a few apps.
        let layout = TileLayout.best(count: visible.count, in: area, label: label, minTile: 44, maxTile: 104)
        let usedColumns = layout.columns
        let usedRows = layout.rows
        let iconSize = layout.tile
        VStack(spacing: 0) {
            if visible.isEmpty {
                WidgetMessage(symbol: "square.grid.3x3", title: "No apps yet",
                              detail: "Drag apps here, or right-click › Edit Widget.")
            } else {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(0..<usedRows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<usedColumns, id: \.self) { column in
                                let index = row * usedColumns + column
                                if index < visible.count {
                                    AppTile(path: visible[index], iconSize: iconSize, showLabel: showLabels,
                                            isRunning: running.isRunning(visible[index]))
                                } else {
                                    Color.clear.frame(width: iconSize, height: iconSize)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetPadding(12)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Layout.cornerRadius - 4, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .padding(4)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            accept(providers)
        }
    }

    private func accept(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, url.pathExtension == "app" else { return }
                DispatchQueue.main.async {
                    var list = model[AppShortcutKeys.apps]
                    if list.isEmpty { list = AppShortcutDefaults.paths() }
                    if !list.contains(url.path) { list.append(url.path) }
                    model.config[AppShortcutKeys.apps] = list
                }
            }
        }
        return accepted
    }
}

private struct AppTile: View {
    let path: String
    let iconSize: CGFloat
    let showLabel: Bool
    let isRunning: Bool
    @State private var hovering = false

    var body: some View {
        Button {
            Shell.openApp(at: path)
        } label: {
            VStack(spacing: 3) {
                Image(nsImage: IconCache.shared.icon(forPath: path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(hovering ? 1.06 : 1)
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                if showLabel {
                    Text(AppShortcutDefaults.displayName(path))
                        .font(.system(size: min(13, 8 + iconSize / 22), weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: iconSize + 14)
                }
                Circle()
                    .fill(Color.primary.opacity(isRunning ? 0.6 : 0))
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .buttonStyle(WidgetButtonStyle())
        .onHover { hovering = $0 }
        .help(AppShortcutDefaults.displayName(path))
        .contextMenu {
            Button("Open") { Shell.openApp(at: path) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
    }
}

// MARK: - Quick actions

enum QuickAction: String, ConfigOption {
    case lockScreen, sleepDisplay, screenSaver, darkMode, screenshot, emptyTrash
    case downloads, activityMonitor, missionControl, terminal, systemSettings, calculator

    var label: String {
        switch self {
        case .lockScreen: return "Lock"
        case .sleepDisplay: return "Display Off"
        case .screenSaver: return "Screen Saver"
        case .darkMode: return "Dark Mode"
        case .screenshot: return "Screenshot"
        case .emptyTrash: return "Empty Trash"
        case .downloads: return "Downloads"
        case .activityMonitor: return "Activity"
        case .missionControl: return "Mission Control"
        case .terminal: return "Terminal"
        case .systemSettings: return "Settings"
        case .calculator: return "Calculator"
        }
    }

    var symbol: String {
        switch self {
        case .lockScreen: return "lock.fill"
        case .sleepDisplay: return "display"
        case .screenSaver: return "sparkles.rectangle.stack.fill"
        case .darkMode: return "circle.lefthalf.filled"
        case .screenshot: return "camera.viewfinder"
        case .emptyTrash: return "trash.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .activityMonitor: return "waveform.path.ecg"
        case .missionControl: return "rectangle.3.group.fill"
        case .terminal: return "terminal.fill"
        case .systemSettings: return "gearshape.fill"
        case .calculator: return "plus.forwardslash.minus"
        }
    }

    var color: Color {
        switch self {
        case .lockScreen: return .gray
        case .sleepDisplay: return .indigo
        case .screenSaver: return .purple
        case .darkMode: return .black
        case .screenshot: return .blue
        case .emptyTrash: return .red
        case .downloads: return .cyan
        case .activityMonitor: return .green
        case .missionControl: return .orange
        case .terminal: return Color(white: 0.2)
        case .systemSettings: return .gray
        case .calculator: return .orange
        }
    }

    @MainActor
    func perform() {
        switch self {
        case .lockScreen:
            Self.lockScreen()
        case .sleepDisplay:
            Shell.launch("/usr/bin/pmset", ["displaysleepnow"])
        case .screenSaver:
            Shell.open(path: "/System/Library/CoreServices/ScreenSaverEngine.app")
        case .darkMode:
            Shell.appleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case .screenshot:
            Shell.open(path: "/System/Applications/Utilities/Screenshot.app")
        case .emptyTrash:
            let alert = NSAlert()
            alert.messageText = "Empty the Trash?"
            alert.informativeText = "You can't undo this action."
            alert.addButton(withTitle: "Empty Trash")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            if alert.runModal() == .alertFirstButtonReturn {
                Shell.appleScript("tell application \"Finder\" to empty trash")
            }
        case .downloads:
            Shell.open(path: FolderStore.downloadsPath)
        case .activityMonitor:
            Shell.openApp(at: "/System/Applications/Utilities/Activity Monitor.app")
        case .missionControl:
            Shell.openApp(at: "/System/Applications/Mission Control.app")
        case .terminal:
            Shell.openApp(at: "/System/Applications/Utilities/Terminal.app")
        case .systemSettings:
            Shell.openApp(at: "/System/Applications/System Settings.app")
        case .calculator:
            Shell.openApp(at: "/System/Applications/Calculator.app")
        }
    }

    private static func lockScreen() {
        let path = "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login"
        if let handle = dlopen(path, RTLD_NOW), let symbol = dlsym(handle, "SACLockScreenImmediate") {
            typealias LockFunction = @convention(c) () -> Int32
            let lock = unsafeBitCast(symbol, to: LockFunction.self)
            _ = lock()
        } else {
            Shell.launch("/usr/bin/pmset", ["displaysleepnow"])
        }
    }
}

enum QuickActionKeys {
    static let actions = ConfigKey<[String]>("actions", ["lockScreen", "darkMode", "screenshot", "sleepDisplay"])
    static let shortcuts = ConfigKey<[String]>("shortcuts", [])
}

struct QuickActionsWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    private enum Item: Identifiable {
        case action(QuickAction)
        case shortcut(String)

        var id: String {
            switch self {
            case .action(let action): return "a:" + action.rawValue
            case .shortcut(let name): return "s:" + name
            }
        }
    }

    private var items: [Item] {
        let actions = model[QuickActionKeys.actions].compactMap(QuickAction.init(rawValue:)).map(Item.action)
        let shortcuts = model[QuickActionKeys.shortcuts].map(Item.shortcut)
        return actions + shortcuts
    }

    var body: some View {
        let dims = model.size.dimensions
        let area = CGSize(width: dims.width - 24, height: dims.height - 24)
        let visible = Array(items.prefix(TileLayout.capacity(in: area, label: 18, spacing: 10, minTile: 40)))
        let layout = TileLayout.best(count: visible.count, in: area, label: 18, spacing: 10, minTile: 40, maxTile: 92)
        let columns = layout.columns, rows = layout.rows
        Group {
            if visible.isEmpty {
                WidgetMessage(symbol: "bolt.circle", title: "No actions", detail: "Right-click › Edit Widget to choose actions and Shortcuts.")
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(0..<rows, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                let index = row * columns + column
                                if index < visible.count {
                                    tile(visible[index], size: layout.tile)
                                } else {
                                    Color.clear.frame(width: 1, height: 1)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetPadding(12)
    }

    @ViewBuilder
    private func tile(_ item: Item, size: CGFloat) -> some View {
        switch item {
        case .action(let action):
            ActionTile(symbol: action.symbol, label: action.label, color: style.tone(action.color), tinted: style == .tinted, size: size) {
                action.perform()
            }
        case .shortcut(let name):
            ActionTile(symbol: "square.2.layers.3d.fill", label: name, color: style.tone(.pink), tinted: style == .tinted, size: size) {
                Shell.launch("/usr/bin/shortcuts", ["run", name])
            }
        }
    }
}

private struct ActionTile: View {
    let symbol: String
    let label: String
    let color: Color
    let tinted: Bool
    var size: CGFloat = 42
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(tinted ? Color.black.opacity(0.75) : Color.white)
                    .frame(width: size, height: size)
                    .background(Circle().fill(color.gradient))
                Text(label)
                    .font(.system(size: min(13, 7.5 + size / 16), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: size + 24)
            }
        }
        .buttonStyle(WidgetButtonStyle())
        .help(label)
    }
}

// MARK: - Folder

enum FolderKeys {
    static let path = ConfigKey("path", "")
}

struct FolderWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var store = FolderStore.shared
    @Environment(\.widgetContext) private var context

    private var path: String {
        let stored = model[FolderKeys.path]
        return stored.isEmpty ? FolderStore.downloadsPath : (stored as NSString).expandingTildeInPath
    }

    private var isSample: Bool { context == .gallery }

    var body: some View {
        content
            .onAppear { if !isSample { store.retain(path) } }
            .onDisappear { if !isSample { store.release(path) } }
            .onChange(of: path) { old, new in
                guard !isSample else { return }
                store.release(old)
                store.retain(new)
            }
    }

    private var items: [FolderStore.Item] {
        if isSample {
            let names = ["Essay Draft.pages", "Screenshot.png", "Worship Setlist.pdf", "Project.zip", "Photo.heic"]
            var samples: [FolderStore.Item] = []
            for (index, name) in names.enumerated() {
                let age = TimeInterval(index) * -5400
                samples.append(FolderStore.Item(id: URL(fileURLWithPath: "/tmp/" + name), name: name,
                                                date: Date().addingTimeInterval(age), size: 1_200_000, isDirectory: false))
            }
            return samples
        }
        return store.items[path] ?? []
    }

    private var title: String { FileManager.default.displayName(atPath: path) }

    @ViewBuilder
    private var content: some View {
        let limit = model.family == .large ? 10 : (model.family == .medium ? 4 : 3)
        VStack(alignment: .leading, spacing: model.family == .small ? 6 : 7) {
            Button {
                Shell.open(path: path)
            } label: {
                WidgetHeader(title: title, symbol: "folder.fill", color: .blue)
            }
            .buttonStyle(WidgetButtonStyle())
            if let error = store.errors[path], !isSample {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if items.isEmpty {
                Text("Folder is empty")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(limit)) { item in
                    FileRow(item: item, compact: model.family == .small, sample: isSample)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }
}

private struct FileRow: View {
    let item: FolderStore.Item
    let compact: Bool
    let sample: Bool

    var body: some View {
        Button {
            if !sample { NSWorkspace.shared.open(item.id) }
        } label: {
            HStack(spacing: 7) {
                Image(nsImage: sample ? NSWorkspace.shared.icon(for: UTType(filenameExtension: item.id.pathExtension) ?? .data)
                                      : IconCache.shared.icon(forPath: item.id.path))
                    .resizable()
                    .frame(width: compact ? 18 : 22, height: compact ? 18 : 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.name)
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !compact {
                        Text(Fmt.ago(item.date) + (item.size.map { " · " + Fmt.disk($0) } ?? ""))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(WidgetButtonStyle())
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(item.id) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.id]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.id.path, forType: .string)
            }
        }
    }
}

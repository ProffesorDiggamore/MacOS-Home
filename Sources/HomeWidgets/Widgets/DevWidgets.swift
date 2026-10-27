import SwiftUI
import AppKit

// Widgets for coding: local dev servers and a repo's Git status. Dev Toolkit is in DevToolsWidget.swift.

// MARK: - Dev servers

/// Everything listening on a TCP port that you started (lsof only sees your own processes).
final class PortsMonitor: PollingMonitor {
    static let shared = PortsMonitor()

    struct Server: Identifiable, Equatable {
        let port: Int
        let process: String
        let localOnly: Bool
        var id: Int { port }

        /// A friendlier name: the framework a port usually means, else the program's name.
        var label: String {
            if let known = Self.wellKnown[port] { return known }
            let lower = process.lowercased()
            if lower.hasPrefix("python") { return "Python" }
            if lower == "node" { return "Node" }
            return process
        }

        private static let wellKnown: [Int: String] = [
            3000: "Dev server", 3001: "Dev server", 4000: "Dev server", 4200: "Angular", 4321: "Astro", 5000: "Flask",
            5173: "Vite", 5174: "Vite", 5432: "Postgres", 6006: "Storybook", 6379: "Redis", 8000: "Python server",
            8080: "Web server", 8081: "Metro", 8888: "Jupyter", 9000: "Dev server", 11434: "Ollama", 27017: "MongoDB", 1313: "Hugo",
        ]
    }

    @Published private(set) var servers: [Server] = []
    @Published private(set) var loaded = false

    override var interval: TimeInterval { 8 }

    /// Background apps that keep a port open but aren't anything you'd want to visit.
    private static let ignored: Set<String> = [
        "rapportd", "ControlCenter", "sharingd", "identityservicesd", "Spotify", "remoted", "UserEventAgent",
        "AirPlayXPCHelper", "Dropbox", "Raycast", "Figma Agent", "OneDrive", "Creative Cloud", "Adobe Desktop Service",
        "LogiMgrDaemon", "Discord", "Steam", "steam_osx", "Code Helper (Plugin)", "Cursor Helper (Plugin)",
    ]

    override func sample() {
        Shell.output("/usr/sbin/lsof", ["+c", "0", "-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]) { [weak self] text in
            guard let self else { return }
            let found = Self.parse(text ?? "")
            if found != self.servers { self.servers = found }
            self.loaded = true
        }
    }

    static func parse(_ text: String) -> [Server] {
        var command = ""
        var byPort: [Int: Server] = [:]
        for line in text.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "c":
                command = value
            case "n":
                guard let colon = value.lastIndex(of: ":"), let port = Int(value[value.index(after: colon)...]) else { continue }
                // Skip apps we know, and the high "ephemeral" ports apps open for themselves.
                guard !ignored.contains(command), port < 49152, byPort[port] == nil else { continue }
                let host = value[..<colon]
                byPort[port] = Server(port: port, process: command, localOnly: host.hasPrefix("127.") || host == "[::1]")
            default:
                break
            }
        }
        return byPort.values.sorted { $0.port < $1.port }
    }

    static let sample: [Server] = [
        Server(port: 3000, process: "node", localOnly: false), Server(port: 5173, process: "node", localOnly: true),
        Server(port: 5432, process: "postgres", localOnly: true), Server(port: 8000, process: "Python", localOnly: false),
    ]
}

struct DevServersWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var monitor = PortsMonitor.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let servers = context == .gallery ? PortsMonitor.sample : monitor.servers
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Dev Servers", symbol: "server.rack", color: .green,
                         trailing: servers.isEmpty || model.family == .small ? nil : "\(servers.count) running")
            if servers.isEmpty {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(monitor.loaded || context == .gallery ? "Nothing running" : "Checking…")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Start a dev server and it shows up here.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else if model.family == .small && model.size != .tall {
                Text("\(servers.count)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(style.tone(.green))
                ForEach(servers.prefix(2)) { row($0, compact: true) }
                Spacer(minLength: 0)
            } else {
                let limit = model.family == .medium ? (model.size == .wide ? 3 : 3) : 8
                let columns = model.family == .medium && servers.count > 3 ? 2 : 1
                let shown = Array(servers.prefix(limit * columns))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), alignment: .leading, spacing: 8) {
                    ForEach(shown) { row($0, compact: false) }
                }
                if servers.count > shown.count {
                    Text("+\(servers.count - shown.count) more").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .widgetPadding()
        .monitoring(if: context == .desktop, monitor)
    }

    private func row(_ server: PortsMonitor.Server, compact: Bool) -> some View {
        Button {
            if let url = URL(string: "http://localhost:\(server.port)") { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(style.tone(.green)).frame(width: 7, height: 7)
                Text(verbatim: ":\(server.port)")
                    .font(.system(size: compact ? 13 : 15, weight: .bold, design: .monospaced))
                    .fixedSize()
                Text(server.label)
                    .font(.system(size: compact ? 11 : 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !compact {
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(WidgetButtonStyle())
        .help("Open http://localhost:\(server.port) (\(server.process))")
    }
}

// MARK: - Git status

enum GitKeys {
    static let path = ConfigKey("gitPath", "")
    static let opener = ConfigKey("gitOpener", GitOpener.terminal)
}

enum GitOpener: String, ConfigOption {
    case terminal, finder, vscode
    var id: String { rawValue }
    var label: String {
        switch self {
        case .terminal: return "Terminal"
        case .finder: return "Finder"
        case .vscode: return "VS Code"
        }
    }

    func open(_ path: String) {
        let url = URL(fileURLWithPath: path)
        switch self {
        case .finder:
            NSWorkspace.shared.open(url)
        case .terminal, .vscode:
            let bundle = self == .terminal ? "com.apple.Terminal" : "com.microsoft.VSCode"
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
                NSWorkspace.shared.open(url)
                return
            }
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

struct GitStatus: Equatable {
    var branch = ""
    var upstream = false
    var ahead = 0
    var behind = 0
    var staged = 0
    var changed = 0
    var untracked = 0
    var conflicts = 0
    var subject = ""
    var committed: Date?
    /// Changed files with a one-letter code: M, A, D, R, ? (new) or U (conflict).
    var files: [(code: String, path: String)] = []

    static func == (a: GitStatus, b: GitStatus) -> Bool {
        a.branch == b.branch && a.upstream == b.upstream && a.ahead == b.ahead && a.behind == b.behind && a.staged == b.staged
            && a.changed == b.changed && a.untracked == b.untracked && a.conflicts == b.conflicts && a.subject == b.subject
            && a.committed == b.committed && a.files.map(\.path) == b.files.map(\.path) && a.files.map(\.code) == b.files.map(\.code)
    }

    var isClean: Bool { staged + changed + untracked + conflicts == 0 }

    /// Reads `git status --porcelain=v2 --branch`.
    static func parse(_ text: String) -> GitStatus {
        var status = GitStatus()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let first = parts.first else { continue }
            switch first {
            case "#":
                if parts.count >= 3, parts[1] == "branch.head" { status.branch = String(parts[2]) }
                if parts.count >= 3, parts[1] == "branch.upstream" { status.upstream = true }
                if parts.count >= 4, parts[1] == "branch.ab" {
                    status.ahead = Int(parts[2].dropFirst()) ?? 0
                    status.behind = Int(parts[3].dropFirst()) ?? 0
                }
            case "1", "2":
                guard parts.count > 1 else { continue }
                let codes = Array(parts[1])
                if codes.count == 2 {
                    if codes[0] != "." { status.staged += 1 }
                    if codes[1] != "." { status.changed += 1 }
                    let path = parts.dropFirst(first == "1" ? 8 : 9).joined(separator: " ").components(separatedBy: "\t")[0]
                    status.files.append((String(codes[0] != "." ? codes[0] : codes[1]), path))
                }
            case "u":
                status.conflicts += 1
                status.files.append(("U", parts.dropFirst(10).joined(separator: " ")))
            case "?":
                status.untracked += 1
                status.files.append(("?", parts.dropFirst().joined(separator: " ")))
            default:
                break
            }
        }
        return status
    }

    static let sample = GitStatus(branch: "main", upstream: true, ahead: 2, behind: 0, staged: 3, changed: 5, untracked: 1,
                                  subject: "Center the grid and stop widgets overlapping", committed: Date().addingTimeInterval(-3600 * 2),
                                  files: [("M", "Sources/App/GridLayout.swift"), ("M", "Sources/App/AppController.swift"), ("A", "Sources/Support/SketchRenderer.swift"),
                                          ("A", "Sources/Widgets/DevWidgets.swift"), ("D", "Sources/Support/AbstractArt.swift"), ("?", "notes.md")])
}

struct GitStatusWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetIsVisible) private var visible
    @Environment(\.widgetStyle) private var style
    @State private var status: GitStatus?
    @State private var failed = false

    private var path: String { (model[GitKeys.path] as NSString).expandingTildeInPath }

    var body: some View {
        let shown = context == .gallery ? GitStatus.sample : status
        let name = context == .gallery ? "MacOS-Home" : URL(fileURLWithPath: path).lastPathComponent
        Group {
            if context != .gallery && model[GitKeys.path].isEmpty {
                WidgetMessage(symbol: "arrow.triangle.branch", title: "Choose a repo", detail: "Pick a folder with a Git repository.",
                              actionTitle: "Choose…", action: choose)
            } else if context != .gallery && failed {
                WidgetMessage(symbol: "questionmark.folder", title: "Not a Git repo", detail: name, actionTitle: "Choose…", action: choose)
            } else {
                content(shown, name: name)
            }
        }
        .task(id: "\(path)|\(visible)") { await poll() }
    }

    @ViewBuilder
    private func content(_ status: GitStatus?, name: String) -> some View {
        let orange = style.tone(.orange)
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: name, symbol: "arrow.triangle.branch", color: .orange,
                         trailing: status.map { sync($0) } ?? nil)
            if let status {
                Text(status.branch.isEmpty ? "—" : status.branch)
                    .font(.system(size: model.family == .small ? 20 : 24, weight: .bold, design: .monospaced))
                    .fitLine(0.5)
                if status.isClean {
                    Label("Clean", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.tone(.green))
                } else if model.family == .small {
                    Text("\(status.staged + status.changed + status.untracked + status.conflicts) changes")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(orange)
                } else {
                    HStack(spacing: 14) {
                        count(status.staged, "staged", .green)
                        count(status.changed, "changed", .orange)
                        count(status.untracked, "new", .gray)
                        if status.conflicts > 0 { count(status.conflicts, "conflicts", .red) }
                    }
                }
                if model.family == .large, !status.files.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(status.files.prefix(7).enumerated()), id: \.offset) { _, file in
                            HStack(spacing: 8) {
                                Text(file.code)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(style.tone(Self.color(for: file.code)))
                                    .frame(width: 12)
                                Text(file.path).font(.system(size: 11.5, design: .monospaced)).lineLimit(1).truncationMode(.head)
                            }
                        }
                        if status.files.count > 7 {
                            Text("+\(status.files.count - 7) more").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                if model.family != .small, !status.subject.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.subject).font(.system(size: 12, weight: .medium)).lineLimit(model.family == .large ? 3 : 1)
                        if let date = status.committed {
                            Text(date, format: .relative(presentation: .named)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                ProgressView().controlSize(.small)
                Spacer(minLength: 0)
            }
        }
        .widgetPadding()
        .contentShape(Rectangle())
        .onTapGesture { if context == .desktop { model[GitKeys.opener].open(path) } }
        .help("Open in \(model[GitKeys.opener].label)")
    }

    private static func color(for code: String) -> Color {
        switch code {
        case "A": return .green
        case "D", "U": return .red
        case "R": return .blue
        case "?": return .gray
        default: return .orange
        }
    }

    private func sync(_ status: GitStatus) -> String? {
        guard status.upstream else { return "local" }
        if status.ahead == 0 && status.behind == 0 { return "up to date" }
        return "↑\(status.ahead) ↓\(status.behind)"
    }

    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(value > 0 ? style.tone(color) : .secondary)
            Text(label).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
        }
    }

    /// Re-reads the repo every 20 seconds while the widget is visible.
    private func poll() async {
        guard context == .desktop, visible, !model[GitKeys.path].isEmpty else { return }
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(nanoseconds: 20_000_000_000)
        }
    }

    private func load() async {
        let repo = path
        let statusText = await run(["-C", repo, "status", "--porcelain=v2", "--branch"])
        guard let statusText, statusText.contains("branch.") else {
            failed = true
            status = nil
            return
        }
        var parsed = GitStatus.parse(statusText)
        if let log = await run(["-C", repo, "log", "-1", "--format=%s%x1f%ct"]) {
            let fields = log.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\u{1f}")
            parsed.subject = fields.first ?? ""
            if fields.count > 1, let seconds = Double(fields[1]) { parsed.committed = Date(timeIntervalSince1970: seconds) }
        }
        failed = false
        if parsed != status { status = parsed }
    }

    private func run(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            Shell.output("/usr/bin/git", arguments) { continuation.resume(returning: $0) }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose Repo"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            model.config[GitKeys.path] = url.path
            failed = false
            status = nil
        }
    }
}

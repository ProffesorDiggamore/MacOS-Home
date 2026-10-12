import AppKit
import Darwin

/// Watches Claude Code's local transcripts (~/.claude/projects) and running `claude`
/// processes to show which sessions are working, which are waiting on you, and today's usage.
final class ClaudeMonitor: PollingMonitor {
    static let shared = ClaudeMonitor()

    enum State: Equatable {
        /// A `claude` process is running and Claude is busy (thinking or using tools).
        case working
        /// A `claude` process is running and Claude has finished its turn.
        case waiting
        /// No process is attached to this session anymore.
        case idle

        var label: String {
            switch self {
            case .working: return "Working"
            case .waiting: return "Your turn"
            case .idle: return ""
            }
        }
    }

    struct Session: Identifiable, Equatable {
        let id: String
        let file: URL
        let projectPath: String
        let title: String
        let lastActivity: Date
        let lastReply: String?
        let model: String?
        let branch: String?
        var state: State
        var pid: pid_t?

        var projectName: String {
            let name = (projectPath as NSString).lastPathComponent
            return name.isEmpty ? projectPath : name
        }
    }

    struct Usage: Equatable {
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var messages = 0
        var total: Int { input + output + cacheRead + cacheWrite }
    }

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var usageToday = Usage()
    @Published private(set) var sessionsToday = 0
    @Published private(set) var isInstalled = true
    @Published private(set) var hasLoaded = false

    override var interval: TimeInterval { 3 }

    private let scanner = ClaudeScanner()
    private let queue = DispatchQueue(label: "HomeWidgets.claude", qos: .utility)
    private var inFlight = false

    var activeCount: Int { sessions.filter { $0.state != .idle }.count }
    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    var workingCount: Int { sessions.filter { $0.state == .working }.count }

    override func sample() {
        guard !inFlight else { return }
        inFlight = true
        let scanner = self.scanner
        queue.async { [weak self] in
            let result = scanner.scan()
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                self.isInstalled = result.installed
                if self.sessions != result.sessions { self.sessions = result.sessions }
                if self.usageToday != result.usage { self.usageToday = result.usage }
                if self.sessionsToday != result.sessionsToday { self.sessionsToday = result.sessionsToday }
                if !self.hasLoaded { self.hasLoaded = true }
            }
        }
    }

    // MARK: Actions

    /// Brings the terminal running a live session forward, or resumes an ended one.
    func open(_ session: Session) {
        if let pid = session.pid, let app = Self.hostApplication(for: pid) {
            _ = app.activate(options: [.activateAllWindows])
            return
        }
        resume(session)
    }

    /// Opens Terminal in the project folder and runs `claude --resume <id>`.
    func resume(_ session: Session) {
        let safeID = String(session.id.filter { $0.isLetter || $0.isNumber || $0 == "-" })
        let script = """
        #!/bin/zsh -il
        cd \(Shell.quote(session.projectPath)) || exit 1
        clear
        exec claude --resume \(safeID)
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-resume-\(safeID).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    /// Starts a brand-new Claude Code session in the same folder.
    func newSession(in projectPath: String) {
        let script = """
        #!/bin/zsh -il
        cd \(Shell.quote(projectPath)) || exit 1
        clear
        exec claude
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-new-\(UUID().uuidString.prefix(8)).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    func revealProject(_ session: Session) {
        NSWorkspace.shared.open(URL(fileURLWithPath: session.projectPath))
    }

    func copySessionID(_ session: Session) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.id, forType: .string)
    }

    /// Walks up the process tree to find the app hosting the terminal (Terminal, iTerm, VS Code…).
    static func hostApplication(for pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<16 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let info = ProcessInfoKit.bsdInfo(current) else { return nil }
            let parent = pid_t(info.pbi_ppid)
            if parent <= 1 || parent == current { return nil }
            current = parent
        }
        return nil
    }

    /// "claude-opus-4-1-20250805" → "Opus 4.1"
    static func prettyModel(_ model: String?) -> String? {
        guard let model, !model.isEmpty else { return nil }
        var parts = model.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, Int(last) != nil { parts.removeLast() }
        let family = parts.first { $0.first?.isLetter == true } ?? "Claude"
        let version = parts.filter { Int($0) != nil }.joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }
}

/// Reads transcripts and process info. Runs only on the monitor's background queue.
final class ClaudeScanner {
    struct Result {
        var sessions: [ClaudeMonitor.Session]
        var usage: ClaudeMonitor.Usage
        var sessionsToday: Int
        var installed: Bool
    }

    private enum LastEntry {
        case unknown, userPrompt, toolResult, assistantText, assistantToolUse, interrupted
    }

    private struct Parsed {
        var cwd: String?
        var prompt: String?
        var summary: String?
        var lastReply: String?
        var model: String?
        var branch: String?
        var last: LastEntry = .unknown
    }

    private struct FileInfo {
        let url: URL
        let modified: Date
        let size: Int
    }

    private struct LiveProcess {
        let pid: pid_t
        let started: Date
    }

    private var parsedCache: [URL: (modified: Date, size: Int, parsed: Parsed)] = [:]
    private var usageOffsets: [URL: UInt64] = [:]
    private var usageDay = Date.distantPast
    private var lastUsageScan = Date.distantPast
    private var seenMessages = Set<String>()
    private var usage = ClaudeMonitor.Usage()
    private let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let isoPlain = ISO8601DateFormatter()

    private var roots: [URL] {
        var list: [URL] = []
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            list.append(URL(fileURLWithPath: (custom as NSString).expandingTildeInPath).appendingPathComponent("projects"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        list.append(home.appendingPathComponent(".claude/projects"))
        list.append(home.appendingPathComponent(".config/claude/projects"))
        return list
    }

    func scan() -> Result {
        let fileManager = FileManager.default
        let existingRoots = roots.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingRoots.isEmpty else {
            return Result(sessions: [], usage: ClaudeMonitor.Usage(), sessionsToday: 0, installed: false)
        }

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        var files: [FileInfo] = []
        for root in existingRoots {
            guard let projects = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for project in projects {
                guard let entries = try? fileManager.contentsOfDirectory(at: project, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
                for url in entries where url.pathExtension == "jsonl" && !url.lastPathComponent.hasPrefix("agent-") {
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    files.append(FileInfo(url: url,
                                          modified: values?.contentModificationDate ?? .distantPast,
                                          size: values?.fileSize ?? 0))
                }
            }
        }
        files.sort { $0.modified > $1.modified }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let sessionsToday = files.filter { $0.modified >= startOfDay }.count
        var live = liveProcesses()
        let now = Date()

        var sessions: [ClaudeMonitor.Session] = []
        for file in files.prefix(12) where file.size > 0 {
            let parsed = parse(file)
            let projectPath = parsed.cwd ?? Self.decodeProjectFolder(file.url.deletingLastPathComponent().lastPathComponent)

            // Attach a running process if one is sitting in this folder and started before the last write.
            var pid: pid_t?
            if var candidates = live[projectPath],
               let index = candidates.firstIndex(where: { $0.started <= file.modified.addingTimeInterval(5) }) {
                pid = candidates.remove(at: index).pid
                live[projectPath] = candidates
            }

            let state: ClaudeMonitor.State
            if pid == nil {
                state = .idle
            } else {
                let age = now.timeIntervalSince(file.modified)
                switch parsed.last {
                case .assistantText, .interrupted:
                    state = age < 3 ? .working : .waiting
                case .unknown:
                    state = .waiting
                default:
                    state = .working
                }
            }

            let title = parsed.summary ?? parsed.prompt ?? "New session"
            sessions.append(ClaudeMonitor.Session(
                id: file.url.deletingPathExtension().lastPathComponent,
                file: file.url,
                projectPath: projectPath,
                title: title,
                lastActivity: file.modified,
                lastReply: parsed.lastReply,
                model: ClaudeMonitor.prettyModel(parsed.model),
                branch: parsed.branch,
                state: state,
                pid: pid))
        }

        // Live sessions first, then most recent.
        sessions.sort { lhs, rhs in
            let left = lhs.state == .idle ? 1 : 0
            let right = rhs.state == .idle ? 1 : 0
            if left != right { return left < right }
            return lhs.lastActivity > rhs.lastActivity
        }

        updateUsage(roots: existingRoots, startOfDay: startOfDay)
        return Result(sessions: sessions, usage: usage, sessionsToday: sessionsToday, installed: true)
    }

    // MARK: Transcript parsing

    private func parse(_ file: FileInfo) -> Parsed {
        if let cached = parsedCache[file.url], cached.modified == file.modified, cached.size == file.size {
            return cached.parsed
        }
        var parsed = parsedCache[file.url]?.parsed ?? Parsed()
        if parsed.cwd == nil || parsed.prompt == nil {
            let head = parseHead(file.url)
            parsed.cwd = parsed.cwd ?? head.cwd
            parsed.prompt = parsed.prompt ?? head.prompt
            parsed.branch = parsed.branch ?? head.branch
            parsed.summary = parsed.summary ?? head.summary
        }
        parseTail(file.url, size: file.size, into: &parsed)
        parsedCache[file.url] = (file.modified, file.size, parsed)
        if parsedCache.count > 200 {
            parsedCache = parsedCache.filter { $0.value.modified > Date().addingTimeInterval(-7 * 86400) }
        }
        return parsed
    }

    private func parseHead(_ url: URL) -> Parsed {
        var parsed = Parsed()
        guard let data = read(url, from: 0, maxBytes: 256 * 1024) else { return parsed }
        for line in lines(in: data, dropFirst: false) {
            guard let object = json(line) else { continue }
            let type = object["type"] as? String
            if parsed.cwd == nil, let cwd = object["cwd"] as? String, !cwd.isEmpty { parsed.cwd = cwd }
            if parsed.branch == nil, let branch = object["gitBranch"] as? String, !branch.isEmpty { parsed.branch = branch }
            if type == "summary", let summary = object["summary"] as? String, !summary.isEmpty { parsed.summary = summary }
            if parsed.prompt == nil, type == "user", (object["isMeta"] as? Bool) != true, let text = promptText(object) {
                parsed.prompt = text
            }
            if parsed.cwd != nil && parsed.prompt != nil && parsed.branch != nil { break }
        }
        return parsed
    }

    private func parseTail(_ url: URL, size: Int, into parsed: inout Parsed) {
        let window = 192 * 1024
        let offset = UInt64(max(0, size - window))
        guard let data = read(url, from: offset, maxBytes: window) else { return }
        for line in lines(in: data, dropFirst: offset > 0) {
            guard let object = json(line) else { continue }
            if let cwd = object["cwd"] as? String, !cwd.isEmpty { parsed.cwd = cwd }
            if let branch = object["gitBranch"] as? String, !branch.isEmpty { parsed.branch = branch }
            switch (object["type"] as? String) ?? "" {
            case "summary":
                if let summary = object["summary"] as? String, !summary.isEmpty { parsed.summary = summary }
            case "assistant":
                guard let message = object["message"] as? [String: Any] else { continue }
                if let model = message["model"] as? String, !model.hasPrefix("<") { parsed.model = model }
                let blocks = message["content"] as? [[String: Any]] ?? []
                if blocks.contains(where: { ($0["type"] as? String) == "tool_use" }) {
                    parsed.last = .assistantToolUse
                } else if let text = blocks.compactMap({ ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }).last {
                    parsed.last = .assistantText
                    parsed.lastReply = Self.oneLine(text, limit: 160)
                }
            case "user":
                if (object["isMeta"] as? Bool) == true { continue }
                guard let message = object["message"] as? [String: Any] else { continue }
                if let blocks = message["content"] as? [[String: Any]],
                   blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) {
                    parsed.last = .toolResult
                } else if let text = rawText(message), text.hasPrefix("[Request interrupted") {
                    parsed.last = .interrupted
                } else {
                    parsed.last = .userPrompt
                    if parsed.prompt == nil { parsed.prompt = promptText(object) }
                }
            default:
                break
            }
        }
    }

    private func rawText(_ message: [String: Any]) -> String? {
        if let text = message["content"] as? String { return text }
        if let blocks = message["content"] as? [[String: Any]] {
            return blocks.compactMap { ($0["type"] as? String) == "text" ? $0["text"] as? String : nil }.first
        }
        return nil
    }

    private func promptText(_ object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any] else { return nil }
        if let blocks = message["content"] as? [[String: Any]],
           blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) { return nil }
        guard let raw = rawText(message)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let command = Self.between(raw, "<command-name>", "</command-name>") {
            let args = Self.between(raw, "<command-args>", "</command-args>") ?? ""
            return Self.oneLine("\(command) \(args)", limit: 140)
        }
        if raw.hasPrefix("<") || raw.hasPrefix("Caveat:") || raw.hasPrefix("[Request interrupted") { return nil }
        return Self.oneLine(raw, limit: 140)
    }

    // MARK: Usage

    private func updateUsage(roots: [URL], startOfDay: Date) {
        if usageDay != startOfDay {
            usageDay = startOfDay
            usageOffsets = [:]
            seenMessages = []
            usage = ClaudeMonitor.Usage()
            lastUsageScan = .distantPast
        }
        guard Date().timeIntervalSince(lastUsageScan) >= 15 else { return }
        lastUsageScan = Date()

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        for root in roots {
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= startOfDay,
                      let size = values.fileSize else { continue }
                consumeUsage(url, size: UInt64(size), startOfDay: startOfDay)
            }
        }
    }

    private func consumeUsage(_ url: URL, size: UInt64, startOfDay: Date) {
        var offset = usageOffsets[url] ?? 0
        if offset > size { offset = 0 }
        let chunk = 4 * 1024 * 1024
        let marker = Data("\"usage\"".utf8)
        while offset < size {
            guard let data = read(url, from: offset, maxBytes: chunk), !data.isEmpty else { break }
            guard let lastNewline = data.lastIndex(of: 0x0A) else {
                // A single enormous line: skip past it once the file has grown beyond this chunk.
                if data.count >= chunk { offset += UInt64(data.count) }
                break
            }
            let complete = data[data.startIndex..<lastNewline]
            offset += UInt64(lastNewline - data.startIndex + 1)
            for line in complete.split(separator: 0x0A) where line.count > 40 && line.range(of: marker) != nil {
                guard let object = json(Data(line)),
                      (object["type"] as? String) == "assistant",
                      let message = object["message"] as? [String: Any],
                      let tokens = message["usage"] as? [String: Any] else { continue }
                if let stamp = object["timestamp"] as? String, let date = parseDate(stamp), date < startOfDay { continue }
                let id = (message["id"] as? String) ?? (object["requestId"] as? String) ?? (object["uuid"] as? String) ?? UUID().uuidString
                guard seenMessages.insert(id).inserted else { continue }
                usage.input += Self.int(tokens["input_tokens"])
                usage.output += Self.int(tokens["output_tokens"])
                usage.cacheRead += Self.int(tokens["cache_read_input_tokens"])
                usage.cacheWrite += Self.int(tokens["cache_creation_input_tokens"])
                usage.messages += 1
            }
        }
        usageOffsets[url] = offset
    }

    // MARK: Processes

    private func liveProcesses() -> [String: [LiveProcess]] {
        var result: [String: [LiveProcess]] = [:]
        let uid = getuid()
        for pid in ProcessInfoKit.allPIDs() {
            guard let info = ProcessInfoKit.bsdInfo(pid), info.pbi_uid == uid, isClaude(pid, info) else { continue }
            guard let cwd = ProcessInfoKit.currentDirectory(pid) else { continue }
            let started = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec))
            result[cwd, default: []].append(LiveProcess(pid: pid, started: started))
        }
        for key in result.keys {
            result[key]?.sort { $0.started > $1.started }
        }
        return result
    }

    private func isClaude(_ pid: pid_t, _ info: proc_bsdinfo) -> Bool {
        let longName = String(cTuple: info.pbi_name)
        let name = longName.isEmpty ? String(cTuple: info.pbi_comm) : longName
        if name == "claude" { return true }
        if name == "node" || name == "bun" || name.hasPrefix("node") {
            return ProcessInfoKit.commandLine(pid).contains("claude")
        }
        // The native installer runs a versioned binary, e.g. ~/.local/share/claude/versions/2.1.0
        if let path = ProcessInfoKit.executablePath(pid) {
            return path.hasSuffix("/claude") || path.contains("/claude/versions/")
        }
        return false
    }

    // MARK: Helpers

    private func read(_ url: URL, from offset: UInt64, maxBytes: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: maxBytes)
        } catch {
            return nil
        }
    }

    private func lines(in data: Data, dropFirst: Bool) -> [Data] {
        var parts = data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
        if dropFirst, !parts.isEmpty { parts.removeFirst() }
        return parts
    }

    private func json(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }

    private func parseDate(_ text: String) -> Date? {
        isoFractional.date(from: text) ?? isoPlain.date(from: text)
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func oneLine(_ text: String, limit: Int) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }

    private static func between(_ text: String, _ start: String, _ end: String) -> String? {
        guard let lower = text.range(of: start), let upper = text.range(of: end, range: lower.upperBound..<text.endIndex) else { return nil }
        let value = text[lower.upperBound..<upper.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Fallback when a transcript has no cwd: "-Users-me-code-app" → "/Users/me/code/app".
    static func decodeProjectFolder(_ name: String) -> String {
        name.replacingOccurrences(of: "-", with: "/")
    }
}

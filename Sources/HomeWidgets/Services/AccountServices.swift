import AppKit
import Combine

// MARK: - GitHub

/// Talks to the GitHub API with a personal access token stored in the Keychain.
final class GitHubService: ObservableObject {
    static let shared = GitHubService()

    struct Item: Identifiable, Equatable {
        enum Kind { case review, pullRequest, notification }
        let id: String
        let kind: Kind
        let title: String
        let repo: String
        let number: Int?
        let url: URL?
        let updated: Date?
        var detail: String?
    }

    struct Day: Identifiable, Equatable {
        var id: String { date }
        let date: String
        let count: Int
        let level: Int
    }

    @Published private(set) var isConnected = false
    @Published private(set) var login: String?
    @Published private(set) var avatar: NSImage?
    @Published private(set) var reviewRequests: [Item] = []
    @Published private(set) var pullRequests: [Item] = []
    @Published private(set) var notifications: [Item] = []
    @Published private(set) var days: [Day] = []
    @Published private(set) var totalContributions = 0
    @Published private(set) var error: String?
    @Published private(set) var lastUpdated: Date?

    private var token: String?
    private var loadedToken = false
    private var clients = 0
    private var timer: AnyCancellable?
    private let decoderDate = ISO8601DateFormatter()

    // MARK: Token

    func loadToken() {
        guard !loadedToken else { return }
        loadedToken = true
        token = Keychain.get("github")
        isConnected = token != nil
    }

    /// The saved token (read from the Keychain once).
    var currentToken: String? {
        loadToken()
        return token
    }

    /// Saves a token and checks it by fetching your profile.
    func connect(token newToken: String, completion: @escaping (String?) -> Void) {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return completion("Paste a token first.") }
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        Self.authorize(&request, token: trimmed)
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == 200, let login = json?["login"] as? String else {
                    completion(status == 401 ? "That token didn't work. Check it and try again." : "Couldn't reach GitHub (status \(status)).")
                    return
                }
                Keychain.set(trimmed, for: "github")
                self.token = trimmed
                self.loadedToken = true
                self.isConnected = true
                self.login = login
                self.loadAvatar(json?["avatar_url"] as? String)
                self.refresh()
                completion(nil)
            }
        }.resume()
    }

    func disconnect() {
        Keychain.set(nil, for: "github")
        token = nil
        isConnected = false
        login = nil
        avatar = nil
        reviewRequests = []
        pullRequests = []
        notifications = []
        days = []
    }

    static func authorize(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("HomeWidgets", forHTTPHeaderField: "User-Agent")
    }

    // MARK: Polling

    func retain() {
        loadToken()
        clients += 1
        if clients == 1 {
            refresh()
            timer = Timer.publish(every: 300, tolerance: 30, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.refresh() }
        }
    }

    func release() {
        clients = max(0, clients - 1)
        if clients == 0 { timer = nil }
    }

    func refresh() {
        guard let token else { return }
        if login == nil { fetchProfile(token) }
        search("is:open is:pr review-requested:@me archived:false", kind: .review, token: token) { [weak self] in self?.reviewRequests = $0 }
        search("is:open is:pr author:@me archived:false", kind: .pullRequest, token: token) { [weak self] in self?.pullRequests = $0 }
        fetchNotifications(token)
        fetchContributions(token)
    }

    // MARK: Requests

    /// Calls the GitHub REST API and hands back JSON on the main thread.
    /// `fresh` skips the URL cache: GitHub marks most responses cacheable for 60 seconds.
    func get(_ path: String, token tokenOverride: String? = nil, fresh: Bool = false, completion: @escaping (Any?, Int) -> Void) {
        loadToken()
        guard let token = tokenOverride ?? token,
              let url = URL(string: path.hasPrefix("http") ? path : "https://api.github.com" + path) else {
            return completion(nil, 0)
        }
        var request = URLRequest(url: url)
        if fresh { request.cachePolicy = .reloadIgnoringLocalCacheData }
        Self.authorize(&request, token: token)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            DispatchQueue.main.async { completion(json, status) }
        }.resume()
    }

    /// Sends a write request (PUT/POST) with a JSON body.
    func send(_ method: String, _ path: String, body: [String: Any], token tokenOverride: String? = nil,
              completion: @escaping (Any?, Int) -> Void) {
        loadToken()
        guard let token = tokenOverride ?? token, let url = URL(string: "https://api.github.com" + path),
              let data = try? JSONSerialization.data(withJSONObject: body) else { return completion(nil, 0) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = data
        Self.authorize(&request, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            DispatchQueue.main.async { completion(json, status) }
        }.resume()
    }

    private func fetchProfile(_ token: String) {
        get("/user") { [weak self] json, status in
            guard let self else { return }
            if status == 401 {
                self.error = "Your GitHub token expired or was revoked. Reconnect it in Accounts."
                return
            }
            guard let user = json as? [String: Any] else { return }
            self.login = user["login"] as? String
            self.loadAvatar(user["avatar_url"] as? String)
        }
    }

    private func loadAvatar(_ link: String?) {
        guard let link, let url = URL(string: link + (link.contains("?") ? "&" : "?") + "s=96") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:))
            DispatchQueue.main.async { self?.avatar = image }
        }.resume()
    }

    private func search(_ query: String, kind: Item.Kind, token: String, apply: @escaping ([Item]) -> Void) {
        var components = URLComponents(string: "https://api.github.com/search/issues")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "per_page", value: "15"),
        ]
        guard let url = components?.url?.absoluteString else { return }
        get(url) { [weak self] json, status in
            guard let self else { return }
            guard status == 200, let items = (json as? [String: Any])?["items"] as? [[String: Any]] else {
                if status == 401 { self.error = "GitHub token isn't valid anymore." }
                return
            }
            self.error = nil
            self.lastUpdated = Date()
            apply(items.map { item in
                let repoURL = item["repository_url"] as? String ?? ""
                let repo = repoURL.components(separatedBy: "/repos/").last ?? ""
                return Item(id: "\(kind)-\(item["id"] as? Int ?? 0)",
                            kind: kind,
                            title: item["title"] as? String ?? "",
                            repo: repo,
                            number: item["number"] as? Int,
                            url: (item["html_url"] as? String).flatMap(URL.init(string:)),
                            updated: (item["updated_at"] as? String).flatMap(self.decoderDate.date(from:)))
            })
        }
    }

    private func fetchNotifications(_ token: String) {
        get("/notifications?per_page=25") { [weak self] json, status in
            guard let self, status == 200, let list = json as? [[String: Any]] else { return }
            self.notifications = list.map { entry in
                let subject = entry["subject"] as? [String: Any] ?? [:]
                let repository = entry["repository"] as? [String: Any] ?? [:]
                let repo = repository["full_name"] as? String ?? ""
                let apiURL = subject["url"] as? String
                let web = apiURL.map {
                    $0.replacingOccurrences(of: "api.github.com/repos", with: "github.com")
                        .replacingOccurrences(of: "/pulls/", with: "/pull/")
                } ?? (repository["html_url"] as? String)
                return Item(id: "n-\(entry["id"] as? String ?? UUID().uuidString)",
                            kind: .notification,
                            title: subject["title"] as? String ?? "",
                            repo: repo,
                            number: nil,
                            url: web.flatMap(URL.init(string:)),
                            updated: (entry["updated_at"] as? String).flatMap(self.decoderDate.date(from:)),
                            detail: (entry["reason"] as? String)?.replacingOccurrences(of: "_", with: " "))
            }
        }
    }

    private func fetchContributions(_ token: String) {
        let query = """
        query { viewer { contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { date contributionCount contributionLevel } } } } } }
        """
        send("POST", "/graphql", body: ["query": query]) { [weak self] json, status in
            guard let self, status == 200,
                  let root = (json as? [String: Any])?["data"] as? [String: Any],
                  let viewer = root["viewer"] as? [String: Any],
                  let collection = viewer["contributionsCollection"] as? [String: Any],
                  let calendar = collection["contributionCalendar"] as? [String: Any],
                  let weeks = calendar["weeks"] as? [[String: Any]] else { return }
            let levels = ["NONE": 0, "FIRST_QUARTILE": 1, "SECOND_QUARTILE": 2, "THIRD_QUARTILE": 3, "FOURTH_QUARTILE": 4]
            var result: [Day] = []
            for week in weeks {
                for day in week["contributionDays"] as? [[String: Any]] ?? [] {
                    result.append(Day(date: day["date"] as? String ?? "",
                                      count: day["contributionCount"] as? Int ?? 0,
                                      level: levels[day["contributionLevel"] as? String ?? ""] ?? 0))
                }
            }
            self.days = result
            self.totalContributions = calendar["totalContributions"] as? Int ?? 0
        }
    }

    /// Current streak of days with at least one contribution (today doesn't break it yet).
    var currentStreak: Int {
        var streak = 0
        for (index, day) in days.reversed().enumerated() {
            if day.count > 0 { streak += 1 } else if index > 0 { break }
        }
        return streak
    }

    static let tokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo,notifications,read:user&description=Home%20Widgets")!
}

// MARK: - Slate notes

/// Reads and writes notes in a Slate (formerly Cairn) vault: Markdown files in a GitHub repo (everything outside `app/`
/// and dot-folders), with daily notes at `Daily/YYYY-MM-DD.md` and emoji icons in `icon:` frontmatter.
final class SlateService: ObservableObject {
    static let shared = SlateService()
    /// Every Slate widget checks back this often (the service skips repeats within five minutes).
    static let refreshTimer = Timer.publish(every: 300, tolerance: 30, on: .main, in: .common).autoconnect()

    struct Note: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let updated: Date?
        var icon: String?
        var title: String {
            let name = (path as NSString).lastPathComponent
            return (name as NSString).deletingPathExtension
        }
    }

    struct Vault: Equatable {
        var recent: [Note] = []
        var noteCount: Int?
        var pinnedText: String?
        var todayText: String?
        /// The note `todayText` came from, so yesterday's isn't shown (or edited) as today's after midnight.
        var todayFile: String?
        var error: String?
        var updated: Date?
        /// Anyone on the internet can read this repo.
        var isPublic = false
        /// Days that have a daily note, as `yyyy-MM-dd`.
        var dailyDates: Set<String> = []
    }

    @Published private(set) var vaults: [String: Vault] = [:]
    @Published private(set) var sending: Set<String> = []
    @Published private(set) var hasOwnToken = false

    private let github = GitHubService.shared
    private var lastRefresh: [String: Date] = [:]
    /// Edits waiting for the one in flight on the same repo; overlapping writes would carry the same sha.
    private var queuedEdits: [String: [() -> Void]] = [:]
    private var icons: [String: String] = [:]
    private let iso = ISO8601DateFormatter()
    private var cachedToken: String?
    private var loadedToken = false

    // MARK: Token

    /// Slate can use its own token (Contents read/write on the vault repo) or fall back to the GitHub one.
    var token: String? {
        loadToken()
        if let cachedToken { return cachedToken }
        return github.currentToken
    }

    var isConnected: Bool { token != nil }

    func loadToken() {
        guard !loadedToken else { return }
        loadedToken = true
        cachedToken = Keychain.get("cairn")
        hasOwnToken = cachedToken != nil
    }

    func setOwnToken(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(trimmed, for: "cairn")
        cachedToken = (trimmed?.isEmpty ?? true) ? nil : trimmed
        loadedToken = true
        hasOwnToken = cachedToken != nil
        lastRefresh = [:]
        objectWillChange.send()
    }

    // MARK: Paths

    static func normalize(_ repo: String) -> String {
        var value = repo.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "https://www.github.com/", "github.com/"] where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        if value.hasSuffix(".git") { value = String(value.dropLast(4)) }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Same rules as Slate's `isVaultNotePath`.
    static func isNote(_ path: String) -> Bool {
        guard path.lowercased().hasSuffix(".md") else { return false }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let first = parts.first, ["app", "node_modules"].contains(first) { return false }
        return !parts.contains { $0.hasPrefix(".") || $0.isEmpty }
    }

    static func dailyPath(folder: String, date: Date = Date()) -> String {
        let name = dayKey(date) + ".md"
        let clean = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return clean.isEmpty ? name : clean + "/" + name
    }

    /// Daily notes are named in Gregorian `yyyy-MM-dd` with Western digits, whatever calendar the Mac uses.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(_ date: Date = Date()) -> String { dayFormatter.string(from: date) }

    static func isDayKey(_ text: String) -> Bool { text.count == 10 && dayFormatter.date(from: text) != nil }

    private static func encodePath(_ path: String) -> String {
        path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
    }

    /// The `icon:` field from a note's YAML frontmatter.
    static func icon(in markdown: String) -> String? {
        guard markdown.hasPrefix("---") else { return nil }
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            if line.hasPrefix("icon:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Markdown without its frontmatter block.
    static func body(of markdown: String) -> String {
        guard markdown.hasPrefix("---") else { return markdown }
        var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).dropFirst()
        while let line = lines.first {
            lines = lines.dropFirst()
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    // MARK: Loading

    func refreshIfNeeded(repo rawRepo: String, folder: String, pinned: String, dailyFolder: String, force: Bool = false) {
        let repo = Self.normalize(rawRepo)
        guard repo.contains("/") else { return }
        guard let token else {
            vaults[repo, default: Vault()].error = "Connect GitHub or add your Slate token in Accounts."
            return
        }
        let key = "\(repo)|\(folder)|\(pinned)|\(dailyFolder)"
        if !force, let last = lastRefresh[key], Date().timeIntervalSince(last) < 300 { return }
        lastRefresh[key] = Date()
        loadNotes(repo: repo, folder: folder, dailyFolder: dailyFolder, token: token)
        loadVisibility(repo: repo, token: token)
        if !pinned.isEmpty {
            loadText(repo: repo, path: Self.inVault(pinned, folder: folder), token: token) { [weak self] text in
                self?.vaults[repo, default: Vault()].pinnedText = text.map(Self.body) ?? "Pinned note not found: \(pinned)"
            }
        }
        let todayFile = Self.inVault(Self.dailyPath(folder: dailyFolder), folder: folder)
        loadText(repo: repo, path: todayFile, token: token) { [weak self] text in
            self?.vaults[repo, default: Vault()].todayText = text.map(Self.body)
            self?.vaults[repo, default: Vault()].todayFile = todayFile
        }
    }

    /// The notes that exist *right now* (the branch's current file tree), ordered by when commits last
    /// touched them. Version 2 listed files straight from commit history, so notes deleted or moved
    /// in Slate kept showing up in the widget.
    private func loadNotes(repo: String, folder: String, dailyFolder: String, token: String) {
        let prefix = Self.folderPrefix(folder)
        let dailyPrefix = Self.inVault(Self.folderPrefix(dailyFolder), folder: folder)
        github.get("/repos/\(repo)/git/trees/HEAD?recursive=1", token: token) { [weak self] json, status in
            guard let self else { return }
            guard status == 200, let tree = (json as? [String: Any])?["tree"] as? [[String: Any]] else {
                self.vaults[repo, default: Vault()].error = status == 404 || status == 409
                    ? "Repo not found or empty. Check the name and that your token can read it."
                    : (status == 401 ? "GitHub rejected the token. Paste a new one in Accounts." : "Couldn't load notes (status \(status)).")
                return
            }
            self.vaults[repo, default: Vault()].error = nil
            let existing = Set(tree.compactMap { entry -> String? in
                guard let path = entry["path"] as? String, (entry["type"] as? String) == "blob",
                      path.hasPrefix(prefix), Self.isNote(String(path.dropFirst(prefix.count))) else { return nil }
                return path
            })
            self.vaults[repo, default: Vault()].noteCount = existing.count
            self.vaults[repo, default: Vault()].dailyDates = Set(existing.compactMap { path -> String? in
                guard path.hasPrefix(dailyPrefix) else { return nil }
                let name = String(path.dropFirst(dailyPrefix.count).dropLast(3))
                return Self.isDayKey(name) ? name : nil
            })
            self.loadRecent(repo: repo, prefix: prefix, existing: existing, token: token)
        }
    }

    private func loadRecent(repo: String, prefix: String, existing: Set<String>, token: String) {
        var path = "/repos/\(repo)/commits?per_page=12"
        if !prefix.isEmpty { path += "&path=" + (String(prefix.dropLast()).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? prefix) }
        github.get(path, token: token) { [weak self] json, status in
            guard let self else { return }
            let commits = (status == 200 ? json as? [[String: Any]] : nil) ?? []
            var dates: [String: Date] = [:]
            var shas: [String] = []
            for commit in commits {
                guard let sha = commit["sha"] as? String else { continue }
                shas.append(sha)
                if let info = commit["commit"] as? [String: Any],
                   let author = info["author"] as? [String: Any],
                   let stamp = author["date"] as? String {
                    dates[sha] = self.iso.date(from: stamp)
                }
            }
            let group = DispatchGroup()
            var details: [String: [[String: Any]]] = [:]
            for sha in shas {
                group.enter()
                self.github.get("/repos/\(repo)/commits/\(sha)", token: token) { json, _ in
                    details[sha] = (json as? [String: Any])?["files"] as? [[String: Any]] ?? []
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                var collected: [Note] = []
                var seen = Set<String>()
                for sha in shas {
                    for file in details[sha] ?? [] {
                        guard let name = file["filename"] as? String,
                              existing.contains(name),
                              seen.insert(name).inserted else { continue }
                        collected.append(Note(path: name, updated: dates[sha], icon: self.icons[name]))
                    }
                }
                // Quiet repo (or notes older than the last few commits): fill up from the tree.
                if collected.count < 10 {
                    for name in existing.sorted() where !seen.contains(name) {
                        collected.append(Note(path: name, updated: nil, icon: self.icons[name]))
                        if collected.count >= 10 { break }
                    }
                }
                let recent = Array(collected.prefix(10))
                self.vaults[repo, default: Vault()].recent = recent
                self.vaults[repo, default: Vault()].updated = Date()
                self.loadIcons(repo: repo, notes: recent, token: token)
            }
        }
    }

    private func loadVisibility(repo: String, token: String) {
        github.get("/repos/\(repo)", token: token) { [weak self] json, status in
            guard let self, status == 200, let object = json as? [String: Any] else { return }
            self.vaults[repo, default: Vault()].isPublic = (object["private"] as? Bool) == false
        }
    }

    /// A note path inside the vault folder (Slate's "Folder in the repo" setting).
    static func inVault(_ path: String, folder: String) -> String {
        let prefix = folderPrefix(folder)
        return path.hasPrefix(prefix) ? path : prefix + path
    }

    static func folderPrefix(_ folder: String) -> String {
        let clean = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        return clean.isEmpty ? "" : clean + "/"
    }

    /// Reads each recent note's frontmatter so the widget can show its emoji icon.
    private func loadIcons(repo: String, notes: [Note], token: String) {
        for note in notes where icons[note.path] == nil {
            loadText(repo: repo, path: note.path, token: token) { [weak self] text in
                guard let self else { return }
                self.icons[note.path] = text.flatMap(Self.icon) ?? ""
                guard var vault = self.vaults[repo] else { return }
                vault.recent = vault.recent.map { item in
                    var copy = item
                    let icon = self.icons[item.path] ?? ""
                    copy.icon = icon.isEmpty ? nil : icon
                    return copy
                }
                self.vaults[repo] = vault
            }
        }
    }

    private func loadText(repo: String, path: String, token: String, completion: @escaping (String?) -> Void) {
        // Fresh, or a refresh just after a tick or capture would bring back the cached note from before it.
        github.get("/repos/\(repo)/contents/\(Self.encodePath(path))", token: token, fresh: true) { json, status in
            guard status == 200, let object = json as? [String: Any], let encoded = object["content"] as? String,
                  let data = Data(base64Encoded: encoded.replacingOccurrences(of: "\n", with: "")) else {
                return completion(nil)
            }
            completion(String(data: data, encoding: .utf8))
        }
    }

    // MARK: Writing

    /// Adds a bullet (or to-do) to a note — today's daily note by default — and commits it.
    /// Slate merges line by line, so this plays nicely with edits made in the app.
    func capture(_ text: String, repo: String, path: String, asTodo: Bool, completion: @escaping (Bool) -> Void) {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return completion(false) }
        edit(repo: repo, path: path, message: "Quick note from Home Widgets", completion: completion) { existing in
            var updated = existing
            if !updated.isEmpty && !updated.hasSuffix("\n") { updated += "\n" }
            return updated + (asTodo ? "- [ ] " : "- ") + line + "\n"
        }
    }

    /// Ticks or unticks a to-do (`- [ ] task` ↔ `- [x] task`): the `occurrence`-th task line whose text is
    /// `task`, counting in note order, so two "Write up" subtasks are told apart.
    func setTodo(_ task: String, occurrence: Int, done: Bool, repo: String, path: String, completion: @escaping (Bool) -> Void) {
        edit(repo: repo, path: path, message: done ? "Done: \(task)" : "Not done: \(task)", completion: completion) { existing in
            var lines = existing.components(separatedBy: "\n")
            let matches = lines.indices.filter { Self.todo(in: lines[$0])?.text == task }
            guard occurrence < matches.count else { return nil }
            let index = matches[occurrence]
            guard Self.todo(in: lines[index])?.done == !done,
                  let box = lines[index].range(of: done ? "[ ]" : "[x]", options: .caseInsensitive) else { return nil }
            lines[index] = lines[index].replacingCharacters(in: box, with: done ? "[x]" : "[ ]")
            return lines.joined(separator: "\n")
        }
    }

    /// A Markdown task line (`- [ ] text`, `* [x] text`), or nil for anything else.
    static func todo(in line: String) -> (text: String, done: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let head = Array(trimmed.prefix(6))
        guard trimmed.count > 6, head[0] == "-" || head[0] == "*", head[1] == " ", head[2] == "[", head[4] == "]", head[5] == " ",
              " xX".contains(head[3]) else { return nil }
        return (String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces), head[3] != " ")
    }

    /// Reads a note, changes it with `transform` (nil = leave it alone) and commits the result.
    /// Edits to one repo run one after another, so each reads the sha the previous one wrote.
    private func edit(repo rawRepo: String, path: String, message: String, completion: @escaping (Bool) -> Void,
                      transform: @escaping (String) -> String?) {
        let repo = Self.normalize(rawRepo)
        guard repo.contains("/"), let token else { return completion(false) }
        let run: () -> Void = { [weak self] in
            self?.write(repo: repo, path: path, message: message, token: token, retry: true, transform: transform) { ok in
                completion(ok)
                self?.nextEdit(repo)
            }
        }
        if sending.contains(repo) {
            queuedEdits[repo, default: []].append(run)
        } else {
            sending.insert(repo)
            run()
        }
    }

    /// Starts the next waiting edit for `repo`, or marks the repo idle.
    private func nextEdit(_ repo: String) {
        guard var queue = queuedEdits[repo], !queue.isEmpty else {
            sending.remove(repo)
            return
        }
        let next = queue.removeFirst()
        queuedEdits[repo] = queue
        next()
    }

    /// One read-change-write. A 409 means the note changed in between (Slate synced), so it re-reads and tries once more.
    private func write(repo: String, path: String, message: String, token: String, retry: Bool,
                       transform: @escaping (String) -> String?, completion: @escaping (Bool) -> Void) {
        let apiPath = "/repos/\(repo)/contents/\(Self.encodePath(path))"
        github.get(apiPath, token: token, fresh: true) { [weak self] json, status in
            guard let self else { return }
            var existing = ""
            var sha: String?
            if status == 200 {
                // A note GitHub won't inline (over 1 MB) must never be replaced by an "empty" one.
                guard let object = json as? [String: Any], let encoded = object["content"] as? String,
                      let data = Data(base64Encoded: encoded.replacingOccurrences(of: "\n", with: "")),
                      let text = String(data: data, encoding: .utf8) else { return completion(false) }
                existing = text
                sha = object["sha"] as? String
            } else if status != 404 {
                return completion(false)
            }
            guard let updated = transform(existing) else { return completion(false) }
            var body: [String: Any] = ["message": message, "content": Data(updated.utf8).base64EncodedString()]
            if let sha { body["sha"] = sha }
            self.github.send("PUT", apiPath, body: body, token: token) { _, putStatus in
                if putStatus == 409 && retry {
                    return self.write(repo: repo, path: path, message: message, token: token, retry: false,
                                      transform: transform, completion: completion)
                }
                let ok = putStatus == 200 || putStatus == 201
                if ok {
                    // Only today's note feeds `todayText`; a capture into Inbox.md used to replace it.
                    if (path as NSString).lastPathComponent == Self.dailyPath(folder: "") {
                        self.vaults[repo, default: Vault()].todayText = Self.body(of: updated)
                        self.vaults[repo, default: Vault()].todayFile = path
                        self.vaults[repo, default: Vault()].dailyDates.insert(Self.dayKey())
                    }
                    self.lastRefresh = [:]
                }
                completion(ok)
            }
        }
    }

    // MARK: Opening

    /// Opens a note in Slate on the web (when the widget has its address) or on GitHub.
    func open(path: String?, repo rawRepo: String, webAddress: String, folder: String = "") {
        let repo = Self.normalize(rawRepo)
        let prefix = Self.folderPrefix(folder)
        let site = webAddress.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !site.isEmpty {
            let base = site.contains("://") ? site : "https://" + site
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-_.!~*'()")
            let hash = path.map { full -> String in
                let inApp = !prefix.isEmpty && full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
                return "#/note/" + (inApp.addingPercentEncoding(withAllowedCharacters: allowed) ?? inApp)
            } ?? "#/"
            if let url = URL(string: base + "/" + hash) {
                NSWorkspace.shared.open(url)
                return
            }
        }
        let suffix = path.map { "/blob/HEAD/" + Self.encodePath($0) } ?? ""
        if let url = URL(string: "https://github.com/\(repo)\(suffix)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Mail

/// Reads unread mail from Apple's Mail app (works with Gmail, iCloud, Outlook… any account added to Mail).
final class MailService: PollingMonitor {
    static let shared = MailService()

    struct Message: Identifiable, Equatable {
        let id: String
        let sender: String
        let subject: String
        let date: Date?
    }

    @Published private(set) var unreadCount: Int?
    @Published private(set) var messages: [Message] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var mailRunning = false

    /// Open Mail hidden in the background when it isn't running, so counts stay fresh.
    var launchInBackground: Bool {
        get { UserDefaults.standard.object(forKey: "mailLaunchInBackground") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "mailLaunchInBackground"); objectWillChange.send() }
    }

    override var interval: TimeInterval { 60 }

    private let queue = DispatchQueue(label: "HomeWidgets.mail", qos: .utility)
    private var inFlight = false
    private static let bundleID = "com.apple.mail"

    override func sample() {
        let running = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == Self.bundleID }
        mailRunning = running
        guard running else {
            if launchInBackground, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.hides = true
                configuration.addsToRecentItems = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.refresh() }
                }
            }
            return
        }
        guard !inFlight else { return }
        inFlight = true
        queue.async { [weak self] in
            let source = """
            tell application "Mail"
                set total to unread count of inbox
                set found to {}
                set unreadMessages to (messages of inbox whose read status is false)
                set n to count of unreadMessages
                if n > 8 then set n to 8
                repeat with i from 1 to n
                    set m to item i of unreadMessages
                    set end of found to {sender of m, subject of m, date received of m, message id of m}
                end repeat
                return {total, found}
            end tell
            """
            let (result, error) = Shell.runAppleScriptNow(source)
            var count: Int?
            var list: [Message] = []
            if let result, result.numberOfItems >= 2 {
                count = Int(result.atIndex(1)?.int32Value ?? 0)
                if let found = result.atIndex(2) {
                    for index in stride(from: 1, through: found.numberOfItems, by: 1) {
                        guard let entry = found.atIndex(index), entry.numberOfItems >= 4 else { continue }
                        let sender = Self.displayName(entry.atIndex(1)?.stringValue ?? "")
                        list.append(Message(id: entry.atIndex(4)?.stringValue ?? UUID().uuidString,
                                            sender: sender,
                                            subject: entry.atIndex(2)?.stringValue ?? "(no subject)",
                                            date: entry.atIndex(3)?.dateValue))
                    }
                }
            }
            list.sort { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                if let count {
                    self.unreadCount = count
                    self.messages = list
                    self.errorMessage = nil
                } else if let error {
                    self.errorMessage = error.contains("Not authorized") || error.contains("-1743")
                        ? "Allow Home Widgets to control Mail in System Settings › Privacy & Security › Automation."
                        : error
                }
            }
        }
    }

    /// "Jane Doe <jane@example.com>" → "Jane Doe"
    static func displayName(_ sender: String) -> String {
        if let bracket = sender.firstIndex(of: "<") {
            let name = sender[..<bracket].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if !name.isEmpty { return name }
        }
        return sender.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    func openMail() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    static let samples: [Message] = [
        Message(id: "1", sender: "Coach Martinez", subject: "Practice moved to 4pm", date: Date().addingTimeInterval(-1800)),
        Message(id: "2", sender: "GitHub", subject: "[MacOS-Home] New review requested", date: Date().addingTimeInterval(-5400)),
        Message(id: "3", sender: "Youth Group", subject: "Retreat sign-ups close Friday", date: Date().addingTimeInterval(-86000)),
    ]
}

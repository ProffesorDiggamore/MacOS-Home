import SwiftUI
import AppKit

// MARK: - GitHub Actions

enum ActionsKeys {
    /// Comma-separated `owner/repo` list; empty follows the repos you pushed to most recently.
    static let repos = ConfigKey("repos", "")
}

/// The latest GitHub Actions run for each repo in a widget's list.
final class ActionsService: ObservableObject {
    static let shared = ActionsService()

    struct Run: Identifiable, Equatable {
        enum State { case passed, failed, running, other }
        var id: String { repo }
        let repo: String
        let workflow: String
        let branch: String
        let state: State
        let updated: Date?
        let url: URL?
        var name: String { repo.split(separator: "/").last.map(String.init) ?? repo }
    }

    /// Keyed by the widget's repo list, so two widgets can follow different repos.
    @Published private(set) var runs: [String: [Run]] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var lastFetch: [String: Date] = [:]
    private let iso = ISO8601DateFormatter()

    static func parse(_ list: String) -> [String] {
        var seen = Set<String>()
        return list.split(whereSeparator: { ", \n".contains($0) }).map { SlateService.normalize(String($0)) }
            .filter { $0.contains("/") && seen.insert($0).inserted }
    }

    func refresh(_ list: String, force: Bool = false) {
        let github = GitHubService.shared
        guard github.currentToken != nil else { return }
        if !force, let last = lastFetch[list], Date().timeIntervalSince(last) < 90 { return }
        lastFetch[list] = Date()
        let repos = Self.parse(list)
        guard repos.isEmpty else { return load(repos, key: list) }
        github.get("/user/repos?sort=pushed&per_page=8&affiliation=owner") { [weak self] json, status in
            guard status == 200 else {
                self?.errors[list] = status == 401 ? "GitHub rejected the token. Paste a new one in Accounts." : "Couldn't list your repos."
                return
            }
            self?.load((json as? [[String: Any]] ?? []).compactMap { $0["full_name"] as? String }, key: list)
        }
    }

    private func load(_ repos: [String], key: String) {
        let group = DispatchGroup()
        var found: [String: Run] = [:]
        var failed: [String: Int] = [:]
        for repo in repos {
            group.enter()
            GitHubService.shared.get("/repos/\(repo)/actions/runs?per_page=1&exclude_pull_requests=true") { [weak self] json, status in
                defer { group.leave() }
                guard status == 200 else { return failed[repo] = status }
                guard let self, let run = ((json as? [String: Any])?["workflow_runs"] as? [[String: Any]])?.first else { return }
                found[repo] = self.run(repo, run)
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            // A repo GitHub didn't answer for keeps its last run instead of vanishing.
            let previous = Dictionary((self.runs[key] ?? []).map { ($0.repo, $0) }, uniquingKeysWith: { first, _ in first })
            // Repos without workflows drop out; the rest keep the order you listed them in.
            let ordered = repos.compactMap { found[$0] ?? (failed[$0] != nil ? previous[$0] : nil) }
            if ordered.isEmpty, let status = failed.values.first {
                self.errors[key] = status == 401 ? "GitHub rejected the token. Paste a new one in Accounts." : "Couldn't reach GitHub."
                return
            }
            self.runs[key] = ordered
            self.errors[key] = ordered.isEmpty ? "No Actions runs yet in \(repos.count == 1 ? repos[0] : "these repos")." : nil
        }
    }

    private func run(_ repo: String, _ object: [String: Any]) -> Run {
        let conclusion = object["conclusion"] as? String ?? ""
        let state: Run.State
        if (object["status"] as? String) != "completed" {
            state = .running
        } else if conclusion == "success" {
            state = .passed
        } else if ["failure", "timed_out", "startup_failure"].contains(conclusion) {
            state = .failed
        } else {
            state = .other
        }
        return Run(repo: repo, workflow: object["name"] as? String ?? "Workflow", branch: object["head_branch"] as? String ?? "",
                   state: state, updated: (object["updated_at"] as? String).flatMap { iso.date(from: $0) },
                   url: (object["html_url"] as? String).flatMap { URL(string: $0) })
    }

    static let samples: [Run] = [
        Run(repo: "you/MacOS-Home", workflow: "Build", branch: "main", state: .running, updated: Date().addingTimeInterval(-60), url: nil),
        Run(repo: "you/slate-web", workflow: "Deploy", branch: "main", state: .passed, updated: Date().addingTimeInterval(-2400), url: nil),
        Run(repo: "you/robotics", workflow: "Tests", branch: "arm-pid", state: .failed, updated: Date().addingTimeInterval(-7200), url: nil),
        Run(repo: "you/apex-rental-pos", workflow: "CI", branch: "main", state: .passed, updated: Date().addingTimeInterval(-86_000), url: nil),
        Run(repo: "you/compendium", workflow: "Lint", branch: "main", state: .passed, updated: Date().addingTimeInterval(-170_000), url: nil),
    ]
}

struct ActionsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = ActionsService.shared
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.widgetContext) private var context

    private static let timer = Timer.publish(every: 120, tolerance: 20, on: .main, in: .common).autoconnect()

    private var key: String { model[ActionsKeys.repos] }
    private var isSample: Bool { context == .gallery }
    private var runs: [ActionsService.Run] { isSample ? ActionsService.samples : service.runs[key] ?? [] }

    var body: some View {
        Group {
            if !isSample && !github.isConnected {
                ConnectGitHubMessage()
            } else if model.family == .small && model.size != .tall {
                small
            } else {
                list
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: key) { _, value in service.refresh(value, force: true) }
        .onReceive(Self.timer) { _ in refresh() }
    }

    private func refresh() {
        if context == .desktop { service.refresh(key) }
    }

    /// Fixed status colours (like Uptime): a theme would turn failing red into running yellow.
    private func symbol(_ state: ActionsService.Run.State) -> (String, Color) {
        switch state {
        case .passed: return ("checkmark.circle.fill", .green)
        case .failed: return ("xmark.circle.fill", .red)
        case .running: return ("arrow.triangle.2.circlepath.circle.fill", .yellow)
        case .other: return ("minus.circle.fill", .gray)
        }
    }

    private var summary: String {
        let failing = runs.filter { $0.state == .failed }.count
        let running = runs.filter { $0.state == .running }.count
        if failing > 0 { return "\(failing) failing" }
        if running > 0 { return "\(running) running" }
        let passed = runs.filter { $0.state == .passed }.count
        return runs.isEmpty ? "" : (passed == runs.count ? "all passing" : "\(passed) of \(runs.count) passing")
    }

    /// The run worth looking at first: failing, then running, then the newest.
    private var headline: ActionsService.Run? {
        runs.first { $0.state == .failed } ?? runs.first { $0.state == .running } ?? runs.first
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Actions", symbol: "checkmark.seal.fill", color: .green)
            Spacer(minLength: 0)
            if let run = headline {
                let (icon, color) = symbol(run.state)
                Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(color)
                Text(summary).font(.system(size: 16, weight: .bold, design: .rounded)).fitLine()
                Text("\(run.name) · \(run.workflow)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Text(service.errors[key] ?? "Loading runs…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { open(headline) }
        .widgetPadding()
    }

    private var list: some View {
        let limit = model.family == .large || model.size == .tall ? 8 : 3
        return VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "GitHub Actions", symbol: "checkmark.seal.fill", color: .green, trailing: summary)
            if runs.isEmpty {
                Text(service.errors[key] ?? "Loading runs…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(runs.prefix(limit)) { run in
                let (icon, color) = symbol(run.state)
                Button { open(run) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(run.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text(run.branch.isEmpty ? run.workflow : "\(run.workflow) · \(run.branch)")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if let updated = run.updated {
                            Text(Fmt.ago(updated)).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(WidgetButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    private func open(_ run: ActionsService.Run?) {
        guard !isSample, let run else { return }
        if let url = run.url ?? URL(string: "https://github.com/\(run.repo)/actions") { NSWorkspace.shared.open(url) }
    }
}

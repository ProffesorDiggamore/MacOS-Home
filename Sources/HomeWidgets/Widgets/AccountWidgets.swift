import SwiftUI
import AppKit

/// Shared "connect your account" message.
private struct ConnectGitHubMessage: View {
    var body: some View {
        WidgetMessage(symbol: "person.crop.circle.badge.plus", title: "Connect GitHub",
                      detail: "Add a GitHub token in Accounts to use this widget.",
                      actionTitle: "Open Accounts") {
            AppController.shared.showSettings(pane: .accounts)
        }
    }
}

// MARK: - GitHub inbox

enum GitHubKeys {
    static let section = ConfigKey("section", GitHubSection.all)
}

enum GitHubSection: String, ConfigOption {
    case all, reviews, pullRequests, notifications

    var label: String {
        switch self {
        case .all: return "Everything"
        case .reviews: return "Review Requests"
        case .pullRequests: return "My Pull Requests"
        case .notifications: return "Notifications"
        }
    }
}

struct GitHubWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.widgetContext) private var context

    private var isSample: Bool { context == .gallery }

    private var items: [GitHubService.Item] {
        if isSample {
            return [
                .init(id: "1", kind: .review, title: "Add Liquid Glass widget style", repo: "you/MacOS-Home", number: 42, url: nil, updated: Date()),
                .init(id: "2", kind: .pullRequest, title: "Fix calendar month grid", repo: "you/MacOS-Home", number: 41, url: nil, updated: Date()),
                .init(id: "3", kind: .notification, title: "Release v2.0 is out", repo: "friend/app", number: nil, url: nil, updated: Date(), detail: "subscribed"),
            ]
        }
        switch model[GitHubKeys.section] {
        case .all: return github.reviewRequests + github.pullRequests + github.notifications
        case .reviews: return github.reviewRequests
        case .pullRequests: return github.pullRequests
        case .notifications: return github.notifications
        }
    }

    var body: some View {
        Group {
            if !isSample && !github.isConnected {
                ConnectGitHubMessage()
            } else {
                switch model.family {
                case .small: small
                case .medium: list(limit: 3)
                case .large: list(limit: 8)
                }
            }
        }
        .onAppear { if !isSample { github.retain() } }
        .onDisappear { if !isSample { github.release() } }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let avatar = github.avatar, !isSample {
                Image(nsImage: avatar).resizable().frame(width: 18, height: 18).clipShape(Circle())
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.purple)
            }
            Text(isSample ? "GitHub" : (github.login.map { "@" + $0 } ?? "GitHub"))
                .font(.system(size: 12.5, weight: .semibold))
            Spacer()
            if let error = github.error, !isSample {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.orange).help(error)
            }
        }
    }

    private func countBlock(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(value > 0 ? color : Color.secondary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 12) {
                countBlock(isSample ? 2 : github.reviewRequests.count, "Reviews", .orange)
                countBlock(isSample ? 3 : github.pullRequests.count, "My PRs", .green)
            }
            countBlock(isSample ? 7 : github.notifications.count, "Notifications", .blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetPadding()
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if items.isEmpty {
                Spacer(minLength: 0)
                Text("All caught up ✨").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            } else {
                ForEach(items.prefix(limit)) { item in
                    GitHubRow(item: item)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }
}

private struct GitHubRow: View {
    let item: GitHubService.Item

    private var icon: (String, Color) {
        switch item.kind {
        case .review: return ("eye.fill", .orange)
        case .pullRequest: return ("arrow.triangle.pull", .green)
        case .notification: return ("bell.fill", .blue)
        }
    }

    var body: some View {
        Button {
            if let url = item.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon.0)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(icon.1)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(item.repo + (item.number.map { " #\($0)" } ?? "") + (item.detail.map { " · " + $0 } ?? ""))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(WidgetButtonStyle())
    }
}

// MARK: - Contributions

struct ContributionsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.colorScheme) private var scheme

    private var isSample: Bool { context == .gallery }

    private var days: [GitHubService.Day] {
        if isSample {
            return (0..<371).map { index in
                let level = Int(seededRandom(index * 7 + 3) * 5)
                return GitHubService.Day(date: "\(index)", count: level * 2, level: level)
            }
        }
        return github.days
    }

    private func color(_ level: Int) -> Color {
        let dark = scheme == .dark
        switch level {
        case 1: return dark ? Color(hex: 0x0E4429) : Color(hex: 0x9BE9A8)
        case 2: return dark ? Color(hex: 0x006D32) : Color(hex: 0x40C463)
        case 3: return dark ? Color(hex: 0x26A641) : Color(hex: 0x30A14E)
        case 4: return dark ? Color(hex: 0x39D353) : Color(hex: 0x216E39)
        default: return Color.primary.opacity(0.08)
        }
    }

    var body: some View {
        Group {
            if !isSample && !github.isConnected {
                ConnectGitHubMessage()
            } else {
                content
            }
        }
        .onAppear { if !isSample { github.retain() } }
        .onDisappear { if !isSample { github.release() } }
    }

    private var content: some View {
        let weeks = max(5, min(53, Int((model.size.dimensions.width - 28) / 14)))
        let visible = Array(days.suffix(weeks * 7 - (7 - todayWeekdayIndex - 1)))
        let total = isSample ? 1_284 : github.totalContributions
        let streak = isSample ? 12 : github.currentStreak
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "square.grid.4x3.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green)
                Text(model.family == .small ? "\(Fmt.count(total))" : "\(Fmt.count(total)) contributions")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text("🔥 \(streak)")
                    .font(.system(size: 12, weight: .semibold))
                    .help("Current streak (days)")
            }
            ContributionGrid(days: visible, weeks: weeks, color: color)
            if model.family == .large {
                Divider().opacity(0.5)
                let best = days.max(by: { $0.count < $1.count })
                HStack {
                    statBlock("This year", Fmt.count(total))
                    statBlock("Streak", "\(streak) days")
                    statBlock("Best day", "\(best?.count ?? 0)")
                }
                Spacer(minLength: 0)
            }
        }
        .widgetPadding()
    }

    /// 0 = Sunday … 6 = Saturday, matching GitHub's calendar rows.
    private var todayWeekdayIndex: Int {
        Calendar(identifier: .gregorian).component(.weekday, from: Date()) - 1
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Columns are weeks (oldest on the left), rows are Sunday → Saturday.
struct ContributionGrid: View {
    let days: [GitHubService.Day]
    let weeks: Int
    let color: (Int) -> Color

    var body: some View {
        let levels = days.map(\.level)
        let paint = color
        let columns = weeks
        return Canvas { context, size in
            let gap: CGFloat = 2.5
            let cell = min((size.width - gap * CGFloat(columns - 1)) / CGFloat(columns), (size.height - gap * 6) / 7)
            for (index, level) in levels.enumerated() {
                let column = index / 7
                let row = index % 7
                guard column < columns else { break }
                let rect = CGRect(x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap), width: cell, height: cell)
                context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.22), with: .color(paint(level)))
            }
        }
        .aspectRatio(CGFloat(columns) / 7, contentMode: .fit)
    }
}

// MARK: - Cairn notes

enum CairnKeys {
    static let repo = ConfigKey("repo", "ProffesorDiggamore/Cairn")
    static let folder = ConfigKey("folder", "")
    static let dailyFolder = ConfigKey("dailyFolder", "Daily")
    static let captureTarget = ConfigKey("captureTarget", CairnCaptureTarget.daily)
    static let inbox = ConfigKey("inbox", "Inbox.md")
    static let asTodo = ConfigKey("asTodo", false)
    static let pinned = ConfigKey("pinned", "")
    static let web = ConfigKey("web", "")
    static let show = ConfigKey("show", CairnLargeContent.today)
}

enum CairnCaptureTarget: String, ConfigOption {
    case daily, note
    var label: String { self == .daily ? "Today's daily note" : "A specific note" }
}

enum CairnLargeContent: String, ConfigOption {
    case today, pinned, recent
    var label: String {
        switch self {
        case .today: return "Today's note"
        case .pinned: return "Pinned note"
        case .recent: return "Recent notes only"
        }
    }
}

struct CairnWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var cairn = CairnService.shared
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.widgetContext) private var context
    @State private var draft = ""
    @State private var flash: String?

    private static let refreshTimer = Timer.publish(every: 300, tolerance: 30, on: .main, in: .common).autoconnect()

    private var isSample: Bool { context == .gallery }
    private var repo: String { CairnService.normalize(model[CairnKeys.repo]) }
    private var capturePath: String {
        CairnService.inVault(model[CairnKeys.captureTarget] == .daily
            ? CairnService.dailyPath(folder: model[CairnKeys.dailyFolder])
            : model[CairnKeys.inbox], folder: model[CairnKeys.folder])
    }

    private var vault: CairnService.Vault {
        if isSample {
            let notes: [(String, String?)] = [("Ideas/App widgets.md", "💡"), ("School/Chem lab notes.md", "🧪"), ("Sermon notes.md", "⛪️"),
                                              ("Daily/2026-10-12.md", "📅"), ("Projects/Robotics.md", "🤖")]
            return CairnService.Vault(recent: notes.map { CairnService.Note(path: $0.0, updated: Date(), icon: $0.1) }, noteCount: 248,
                                      pinnedText: nil,
                                      todayText: "- Finish chem lab\n- [ ] Robotics meeting Thursday\n- Read Proverbs 3",
                                      error: nil, updated: Date())
        }
        return cairn.vaults[repo] ?? CairnService.Vault()
    }

    var body: some View {
        Group {
            if !isSample && !cairn.isConnected {
                WidgetMessage(symbol: "mountain.2", title: "Connect Cairn",
                              detail: "Paste your Cairn or GitHub token in Accounts.",
                              actionTitle: "Open Accounts") {
                    AppController.shared.showSettings(pane: .accounts)
                }
            } else if !isSample && !repo.contains("/") {
                WidgetMessage(symbol: "mountain.2", title: "Set your Cairn repo",
                              detail: "Right-click › Edit Widget and enter the repo Cairn syncs to (like you/Cairn).")
            } else {
                switch model.family {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: model.config) { _, _ in refresh() }
        .onReceive(Self.refreshTimer) { _ in refresh() }
    }

    private func refresh() {
        guard !isSample else { return }
        _ = github.currentToken
        cairn.refreshIfNeeded(repo: repo, folder: model[CairnKeys.folder], pinned: model[CairnKeys.pinned],
                              dailyFolder: model[CairnKeys.dailyFolder])
    }

    private func open(_ path: String?) {
        guard !isSample else { return }
        cairn.open(path: path, repo: repo, webAddress: model[CairnKeys.web], folder: model[CairnKeys.folder])
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.teal)
            Text("Cairn")
                .font(.system(size: 12.5, weight: .semibold))
            if vault.isPublic && !isSample {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("This notes repo is public — anyone can read it. Make it private on GitHub, or move your notes to a private repo (see Cairn › Settings › Sync).")
            }
            Spacer()
            if let count = vault.noteCount {
                Text("\(count) notes")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Button {
                open(CairnService.inVault(CairnService.dailyPath(folder: model[CairnKeys.dailyFolder]), folder: model[CairnKeys.folder]))
            } label: {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(WidgetButtonStyle())
            .help("Open today's note")
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Spacer(minLength: 0)
            if let note = vault.recent.first {
                Text("Last edited")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let icon = note.icon { CairnIcon(value: icon, size: 16) }
                    Text(note.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                }
                if let updated = note.updated {
                    Text(Fmt.ago(updated)).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            } else {
                Text(vault.error ?? "Loading notes…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { open(vault.recent.first?.path) }
        .widgetPadding()
    }

    private func notes(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = vault.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(vault.recent.prefix(limit)) { note in
                Button {
                    open(note.path)
                } label: {
                    HStack(spacing: 6) {
                        if let icon = note.icon {
                            CairnIcon(value: icon, size: 13)
                        } else {
                            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(Color.teal)
                        }
                        Text(note.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let updated = note.updated {
                            Text(Fmt.ago(updated)).font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(WidgetButtonStyle())
            }
        }
    }

    private var captureField: some View {
        HStack(spacing: 6) {
            TextField(flash ?? (model[CairnKeys.captureTarget] == .daily ? "Add to today's note…" : "Add to \(model[CairnKeys.inbox])…"),
                      text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit(send)
                .disabled(isSample)
            if cairn.sending.contains(repo) {
                ProgressView().controlSize(.small)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(draft.isEmpty ? Color.secondary : Color.teal)
                }
                .buttonStyle(WidgetButtonStyle())
                .disabled(draft.isEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
    }

    private func send() {
        let text = draft
        guard !text.isEmpty else { return }
        draft = ""
        cairn.capture(text, repo: repo, path: capturePath, asTodo: model[CairnKeys.asTodo]) { ok in
            flash = ok ? "Saved ✓ It'll show up in Cairn on its next sync." : "Couldn't save. Does the token have Contents write access?"
            if !ok { draft = text }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            notes(limit: 3)
            Spacer(minLength: 0)
            captureField
        }
        .widgetPadding()
    }

    private var large: some View {
        let show = model[CairnKeys.show]
        let text: String? = show == .today ? (vault.todayText ?? "") : (show == .pinned ? vault.pinnedText : nil)
        return VStack(alignment: .leading, spacing: 8) {
            header
            if let text {
                Text(show == .today ? "Today · \(DateFormats.string(Date(), template: "EEEEMMMd"))" : (model[CairnKeys.pinned] as NSString).deletingPathExtension)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    if text.isEmpty {
                        Text("Nothing yet today. Add something below.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        MarkdownText(text).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: model.size == .portrait ? 260 : 140)
                Divider().opacity(0.5)
                notes(limit: model.size == .portrait ? 8 : 4)
            } else {
                notes(limit: 9)
            }
            Spacer(minLength: 0)
            captureField
        }
        .widgetPadding()
    }
}

/// Renders a little Markdown (headings, bullets, bold/italic, links) line by line.
struct MarkdownText: View {
    let source: String

    init(_ source: String) {
        self.source = source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(source.split(separator: "\n", omittingEmptySubsequences: false).prefix(40).enumerated()), id: \.offset) { _, rawLine in
                line(String(rawLine))
            }
        }
    }

    @ViewBuilder
    private func line(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") {
            Text(inline(String(trimmed.dropFirst(2)))).font(.system(size: 15, weight: .bold))
        } else if trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ") {
            Text(inline(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces))).font(.system(size: 13, weight: .bold))
        } else if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: trimmed.hasPrefix("- [x] ") ? "checkmark.square.fill" : "square").font(.system(size: 10))
                Text(inline(String(trimmed.dropFirst(6)))).font(.system(size: 12))
            }
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("•").font(.system(size: 12, weight: .bold))
                Text(inline(String(trimmed.dropFirst(2)))).font(.system(size: 12))
            }
        } else if trimmed.isEmpty {
            Color.clear.frame(height: 2)
        } else {
            Text(inline(trimmed)).font(.system(size: 12))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Mail

struct MailWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var mail = MailService.shared
    @Environment(\.widgetContext) private var context

    private var isSample: Bool { context == .gallery }
    private var messages: [MailService.Message] { isSample ? MailService.samples : mail.messages }
    private var unread: Int? { isSample ? 3 : mail.unreadCount }

    var body: some View {
        Ticking(everySecond: false) { now in
            Group {
                if let error = mail.errorMessage, !isSample {
                    WidgetMessage(symbol: "envelope.badge.shield.half.filled", title: "Mail needs permission", detail: error)
                } else {
                    switch model.family {
                    case .small: small(now)
                    case .medium: list(now, limit: 3)
                    case .large: list(now, limit: 8)
                    }
                }
            }
        }
        .monitoring(if: !isSample, MailService.shared)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.blue)
            Text("Mail").font(.system(size: 12.5, weight: .semibold))
            Spacer()
            if let unread {
                Text("\(unread) unread").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            }
        }
    }

    private func small(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.blue)
            Spacer(minLength: 0)
            Text(unread.map { String($0) } ?? "–")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text("unread")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if let first = messages.first {
                Text(first.sender)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { mail.openMail() }
        .widgetPadding()
    }

    private func list(_ now: Date, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if messages.isEmpty {
                Spacer(minLength: 0)
                Text(unread == nil ? (mail.mailRunning ? "Checking…" : "Opening Mail…") : "Inbox zero 🎉")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(messages.prefix(limit)) { message in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Color.blue).frame(width: 7, height: 7).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(message.sender).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                Spacer(minLength: 4)
                                if let date = message.date {
                                    Text(Fmt.ago(date, now: now)).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                            }
                            Text(message.subject).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { mail.openMail() }
        .widgetPadding()
    }
}

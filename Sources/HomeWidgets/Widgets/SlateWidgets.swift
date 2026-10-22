import SwiftUI
import AppKit

// MARK: - Brand

/// Slate (formerly Cairn) colours and links. The widgets follow your widget style, or sit on Slate's stone grey.
enum Slate {
    static let stone = Color(hex: 0x3A424B)
    static let background = CustomBackground.gradient(Color(hex: 0x4A545F), Color(hex: 0x2B3138))
    static let web = "slatenotes.netlify.app"

    /// The logo's colour, as on Slate's favicon: near-white on dark backgrounds, stone on light ones.
    static func ink(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xEEF1F4) : stone }
    /// Rings, ticks and written days. Kept below the colour themes' saturation cut-off so a theme never turns them blue.
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xB9C3CD) : Color(hex: 0x5E656D) }
}

/// Slate's logo, three stacked slabs, traced from Slate's favicon (a 100 × 100 grid).
struct SlateLogo: Shape {
    private static let slabs: [[CGFloat]] = [
        [34.2, 31.9, 53.8, 11.0, 61.6, 29.8, 46.5, 36.0, 35.8, 33.7],
        [24.0, 51.7, 29.3, 45.4, 65.5, 32.7, 72.8, 45.4, 60.6, 60.3, 25.3, 53.0],
        [15.2, 77.5, 32.4, 60.0, 73.9, 67.9, 84.8, 78.0, 34.5, 89.0],
    ]

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 100
        let x = rect.midX - 50 * scale, y = rect.midY - 50 * scale
        var path = Path()
        for slab in Self.slabs {
            path.addLines(stride(from: 0, to: slab.count, by: 2).map { CGPoint(x: x + slab[$0] * scale, y: y + slab[$0 + 1] * scale) })
            path.closeSubpath()
        }
        return path
    }

    /// The logo as a template image for menus.
    static let menuImage: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: SlateLogo().path(in: rect).cgPath).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

/// A widget kind's glyph in the gallery and widget list: its SF Symbol, or the logo for Slate widgets.
struct KindGlyph: View {
    let kind: WidgetKind
    let size: CGFloat

    var body: some View {
        if kind.isSlate {
            SlateLogo().fill(Color.white).frame(width: size * 1.35, height: size * 1.35)
        } else {
            Image(systemName: kind.symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(Color.white)
        }
    }
}

extension View {
    /// Slate's stone background with light text when `stone` is on; otherwise the chosen widget style.
    @ViewBuilder
    func slateBackground(_ stone: Bool) -> some View {
        if stone {
            environment(\.colorScheme, .dark).widgetBackground(Slate.background)
        } else {
            self
        }
    }
}

// MARK: - Settings

enum SlateKeys {
    static let repo = ConfigKey("repo", "ProffesorDiggamore/Cairn")
    static let folder = ConfigKey("folder", "")
    static let dailyFolder = ConfigKey("dailyFolder", "Daily")
    static let captureTarget = ConfigKey("captureTarget", SlateCaptureTarget.daily)
    static let inbox = ConfigKey("inbox", "Inbox.md")
    static let asTodo = ConfigKey("asTodo", false)
    static let pinned = ConfigKey("pinned", "")
    static let web = ConfigKey("web", Slate.web)
    static let show = ConfigKey("show", SlateLargeContent.today)
    /// Slate's stone-grey background instead of the widget style (Frosted Glass, Liquid Glass…).
    static let stone = ConfigKey("stone", false)
}

enum SlateCaptureTarget: String, ConfigOption {
    case daily, note
    var label: String { self == .daily ? "Today's daily note" : "A specific note" }
}

enum SlateLargeContent: String, ConfigOption {
    case today, pinned, recent
    var label: String {
        switch self {
        case .today: return "Today's note"
        case .pinned: return "Pinned note"
        case .recent: return "Recent notes only"
        }
    }
}

// MARK: - Shared

/// What every Slate widget does: find its vault, keep it fresh and open notes.
@MainActor
protocol SlateVaultWidget: View {
    var model: WidgetModel { get }
    var context: WidgetContext { get }
    var scheme: ColorScheme { get }
    var look: WidgetLook { get }
}

extension SlateVaultWidget {
    var isSample: Bool { context == .gallery }
    /// Accent for this widget's background (the stone background is always dark); white on Tinted, like other widgets.
    var accent: Color { look.tone(Slate.accent(model[SlateKeys.stone] ? .dark : scheme)) }
    var repo: String { SlateService.normalize(model[SlateKeys.repo]) }
    var todayPath: String {
        SlateService.inVault(SlateService.dailyPath(folder: model[SlateKeys.dailyFolder]), folder: model[SlateKeys.folder])
    }

    var vault: SlateService.Vault {
        isSample ? SlateService.Vault.sample : SlateService.shared.vaults[repo] ?? SlateService.Vault()
    }

    /// Today's note, or nil while the vault still holds another day's (just after midnight, until the next refresh).
    var todayText: String? {
        let vault = vault
        return isSample || vault.todayFile == todayPath ? vault.todayText : nil
    }

    /// Asks the user to connect or pick a repo until the vault can be read.
    var setupMessage: WidgetMessage? {
        if isSample { return nil }
        if !SlateService.shared.isConnected {
            return WidgetMessage(symbol: "square.stack.3d.up", title: "Connect Slate",
                                 detail: "Paste your Slate or GitHub token in Accounts.", actionTitle: "Open Accounts") {
                AppController.shared.showSettings(pane: .accounts)
            }
        }
        if !repo.contains("/") {
            return WidgetMessage(symbol: "square.stack.3d.up", title: "Set your Slate repo",
                                 detail: "Right-click › Edit Widget and enter the repo Slate syncs to (like you/notes).")
        }
        return nil
    }

    func refresh() {
        guard !isSample else { return }
        _ = GitHubService.shared.currentToken
        SlateService.shared.refreshIfNeeded(repo: repo, folder: model[SlateKeys.folder], pinned: model[SlateKeys.pinned],
                                            dailyFolder: model[SlateKeys.dailyFolder])
    }

    func open(_ path: String?) {
        guard !isSample else { return }
        SlateService.shared.open(path: path, repo: repo, webAddress: model[SlateKeys.web], folder: model[SlateKeys.folder])
    }

    /// Body wrapper: setup message or content, Slate colours, refreshing every five minutes.
    func slateFrame<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Group {
            if let setupMessage { setupMessage } else { content() }
        }
        .slateBackground(model[SlateKeys.stone])
        .onAppear(perform: refresh)
        .onChange(of: model.config) { _, _ in refresh() }
        .onReceive(SlateService.refreshTimer) { _ in refresh() }
        // Load straight away once a token is added in Accounts, instead of at the next timer tick.
        // (Gallery previews never read the token: that would ask for Keychain access.)
        .onChange(of: !isSample && SlateService.shared.isConnected) { _, _ in refresh() }
    }
}

/// Logo, title and an optional trailing view.
struct SlateHeader<Trailing: View>: View {
    let title: String
    var warnPublic = false
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            SlateLogo().fill(Slate.ink(scheme)).frame(width: 15, height: 15)
            Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
            if warnPublic {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .help("This notes repo is public — anyone can read it. Make it private on GitHub, or move your notes to a private repo (Slate › Settings › Sync).")
            }
            Spacer(minLength: 4)
            trailing()
        }
    }
}

/// One-line quick capture box. `send` reports whether the note was saved.
struct SlateCaptureField: View {
    let placeholder: String
    let busy: Bool
    let disabled: Bool
    let send: (String, @escaping (Bool) -> Void) -> Void
    @State private var draft = ""
    @State private var flash: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            TextField(flash ?? placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit(submit)
                .disabled(disabled)
            if busy {
                ProgressView().controlSize(.small)
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(draft.isEmpty ? Color.secondary : Slate.accent(scheme))
                }
                .buttonStyle(WidgetButtonStyle())
                .disabled(draft.isEmpty)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
    }

    private func submit() {
        let text = draft
        guard !text.isEmpty else { return }
        draft = ""
        send(text) { ok in
            flash = ok ? "Saved ✓ Slate picks it up on its next sync." : "Couldn't save. Does the token have Contents write access?"
            if !ok { draft = text }
        }
    }
}

extension SlateService.Vault {
    static let sample: SlateService.Vault = {
        let notes: [(String, String?)] = [("Ideas/App widgets.md", "💡"), ("School/Chem lab notes.md", "🧪"), ("Sermon notes.md", "⛪️"),
                                          ("Daily/2026-10-12.md", "📅"), ("Projects/Robotics.md", "🤖")]
        var vault = SlateService.Vault(recent: notes.map { SlateService.Note(path: $0.0, updated: Date(), icon: $0.1) }, noteCount: 248,
                                       todayText: "- [x] Finish chem lab\n- [ ] Robotics meeting Thursday\n- [ ] Read Proverbs 3\n- [x] Email Coach\n- Pick up poster board",
                                       updated: Date())
        for day in 0..<140 where day < 9 || seededRandom(day * 13 + 5) > 0.3 {
            vault.dailyDates.insert(SlateService.dayKey(Date().addingTimeInterval(-86_400 * Double(day))))
        }
        return vault
    }()
}

// MARK: - Slate Notes

struct SlateNotesWidget: View, SlateVaultWidget {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var slate = SlateService.shared
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.widgetContext) var context
    @Environment(\.colorScheme) var scheme
    @Environment(\.widgetStyle) var look

    private var capturePath: String {
        model[SlateKeys.captureTarget] == .daily ? todayPath : SlateService.inVault(model[SlateKeys.inbox], folder: model[SlateKeys.folder])
    }

    var body: some View {
        slateFrame {
            switch model.family {
            case .small where model.size == .tall: tall
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
    }

    private var header: some View {
        SlateHeader(title: "Slate", warnPublic: vault.isPublic && !isSample) {
            if let count = vault.noteCount, model.size != .small {
                Text("\(count) notes").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
            }
            Button { open(todayPath) } label: {
                Image(systemName: "calendar").font(.system(size: 11, weight: .semibold))
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
                Text("Last edited").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let icon = note.icon { SlateIcon(value: icon, size: 16) }
                    Text(note.title).font(.system(size: 15, weight: .semibold)).lineLimit(2)
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
                Button { open(note.path) } label: {
                    HStack(spacing: 6) {
                        if let icon = note.icon {
                            SlateIcon(value: icon, size: 13)
                        } else {
                            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(accent)
                        }
                        Text(note.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
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
        SlateCaptureField(placeholder: model[SlateKeys.captureTarget] == .daily ? "Add to today's note…" : "Add to \(model[SlateKeys.inbox])…",
                          busy: slate.sending.contains(repo), disabled: isSample) { text, done in
            slate.capture(text, repo: repo, path: capturePath, asTodo: model[SlateKeys.asTodo], completion: done)
        }
    }

    /// Tall: your most recent notes, top to bottom.
    private var tall: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            notes(limit: 8)
            Spacer(minLength: 0)
        }
        .widgetPadding()
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
        let show = model[SlateKeys.show]
        let text: String? = show == .today ? (todayText ?? "") : (show == .pinned ? vault.pinnedText : nil)
        let title = show == .today ? "Today · \(DateFormats.string(Date(), template: "EEEEMMMd"))" : (model[SlateKeys.pinned] as NSString).deletingPathExtension
        return VStack(alignment: .leading, spacing: 8) {
            header
            if let text, !text.isEmpty {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                // The note takes whatever room the recent list leaves.
                ScrollView {
                    MarkdownText(text).frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: .infinity)
                Divider().opacity(0.5)
                notes(limit: model.size == .portrait ? 6 : 3)
            } else {
                if text != nil {
                    Text("\(title) — nothing yet. Add something below.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .fitLine(0.8)
                }
                // No note to show, so the recent list fills the space instead of a blank box.
                notes(limit: model.size == .portrait ? 15 : 9)
                Spacer(minLength: 0)
            }
            captureField
        }
        .widgetPadding()
    }
}

// MARK: - Slate Today

/// The to-dos in today's daily note. Click one to tick it off in Slate.
struct SlateTodayWidget: View, SlateVaultWidget {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var slate = SlateService.shared
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.widgetContext) var context
    @Environment(\.colorScheme) var scheme
    @Environment(\.widgetStyle) var look
    /// Ticks shown straight away while GitHub saves them.
    @State private var pending: [Int: Bool] = [:]
    @State private var failed = false

    private struct Task: Identifiable {
        /// Position among the note's to-dos.
        let id: Int
        /// How many earlier to-dos have the same text, so the right one is ticked.
        let occurrence: Int
        let text: String
        let done: Bool
    }

    /// Open to-dos first, in note order, then the finished ones.
    private var tasks: [Task] {
        var seen: [String: Int] = [:]
        let all = (todayText ?? "").components(separatedBy: "\n").compactMap(SlateService.todo).enumerated().map { index, todo -> Task in
            defer { seen[todo.text, default: 0] += 1 }
            return Task(id: index, occurrence: seen[todo.text] ?? 0, text: todo.text, done: pending[index] ?? todo.done)
        }
        return all.filter { !$0.done } + all.filter(\.done)
    }

    var body: some View {
        slateFrame {
            let tasks = tasks
            let done = tasks.filter(\.done).count
            switch model.family {
            case .small: small(tasks, done: done)
            case .medium: medium(tasks, done: done)
            case .large: large(tasks, done: done)
            }
        }
    }

    private func ring(_ tasks: [Task], done: Int, size: CGFloat) -> some View {
        RingGauge(value: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count), color: accent, lineWidth: size * 0.1) {
            VStack(spacing: 0) {
                Text("\(done)/\(tasks.count)").font(.system(size: size * 0.24, weight: .bold, design: .rounded)).fitLine()
                Text("done").font(.system(size: size * 0.12, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }

    private var title: String { "Today · " + DateFormats.string(Date(), template: "EEEMMMd") }

    private var emptyText: String {
        todayText == nil ? (vault.error ?? "No daily note yet today.") : "No to-dos in today's note."
    }

    private func small(_ tasks: [Task], done: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SlateHeader(title: "Today") { EmptyView() }
            Spacer(minLength: 0)
            HStack { Spacer(); ring(tasks, done: done, size: 74); Spacer() }
            Spacer(minLength: 0)
            Text(tasks.first(where: { !$0.done })?.text ?? (tasks.isEmpty ? emptyText : "All done 🎉"))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { open(todayPath) }
        .widgetPadding()
    }

    private func medium(_ tasks: [Task], done: Int) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                SlateHeader(title: "Today") { EmptyView() }
                Spacer(minLength: 0)
                ring(tasks, done: done, size: 78)
                Spacer(minLength: 0)
            }
            .frame(width: 96)
            list(tasks, limit: model.size == .wide ? 5 : 4)
        }
        .widgetPadding()
    }

    private func large(_ tasks: [Task], done: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SlateHeader(title: title) {
                Text("\(done) of \(tasks.count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            let progress = tasks.isEmpty ? 0 : CGFloat(done) / CGFloat(tasks.count)
            Capsule().fill(Color.primary.opacity(0.1))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in Capsule().fill(accent).frame(width: max(5, geo.size.width * progress)) }
                }
                .frame(height: 5)
            list(tasks, limit: model.size == .portrait ? 16 : 10)
            SlateCaptureField(placeholder: "Add a to-do for today…", busy: slate.sending.contains(repo), disabled: isSample) { text, finished in
                slate.capture(text, repo: repo, path: todayPath, asTodo: true, completion: finished)
            }
        }
        .widgetPadding()
    }

    private func list(_ tasks: [Task], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if tasks.isEmpty {
                Text(emptyText).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            ForEach(tasks.prefix(limit)) { task in
                Button { toggle(task) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(task.done ? accent : Color.secondary)
                        Text(inline(task.text))
                            .font(.system(size: 12, weight: .medium))
                            .strikethrough(task.done, color: .secondary)
                            .foregroundStyle(task.done ? .secondary : .primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(WidgetButtonStyle())
            }
            if tasks.count > limit {
                Text("+\(tasks.count - limit) more").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            if failed {
                Text("Couldn't save. Does the token have write access?").font(.system(size: 10.5)).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggle(_ task: Task) {
        guard !isSample else { return }
        pending[task.id] = !task.done
        failed = false
        slate.setTodo(task.text, occurrence: task.occurrence, done: !task.done, repo: repo, path: todayPath) { ok in
            pending[task.id] = nil
            failed = !ok
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Slate Streak

/// A heat map of the days you wrote a daily note, plus your current streak.
struct SlateStreakWidget: View, SlateVaultWidget {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var slate = SlateService.shared
    @ObservedObject private var github = GitHubService.shared
    @Environment(\.widgetContext) var context
    @Environment(\.colorScheme) var scheme
    @Environment(\.widgetStyle) var look

    var body: some View {
        slateFrame {
            let dates = vault.dailyDates
            if model.family == .small {
                small(dates)
            } else {
                grid(dates)
            }
        }
    }

    /// Consecutive days with a note, counting back from today (or yesterday, before today's is written).
    private func streak(_ dates: Set<String>) -> Int {
        var day = Date()
        if !dates.contains(key(day)) { day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while dates.contains(key(day)) {
            count += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    private func key(_ date: Date) -> String { SlateService.dayKey(date) }

    private func small(_ dates: Set<String>) -> some View {
        let calendar = Calendar.current
        let week = (0..<7).reversed().map { calendar.date(byAdding: .day, value: -$0, to: Date()) ?? Date() }
        return VStack(alignment: .leading, spacing: 4) {
            SlateHeader(title: "Streak") { EmptyView() }
            Spacer(minLength: 0)
            Text("\(streak(dates))").font(.system(size: 44, weight: .bold, design: .rounded)).fitLine()
            Text("days in a row").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                ForEach(week, id: \.self) { day in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(dates.contains(key(day)) ? accent : Color.primary.opacity(0.1))
                            .frame(width: 11, height: 11)
                        Text(DateFormats.string(day, format: "EEEEE")).font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(todayPath) }
        .widgetPadding()
    }

    private func grid(_ dates: Set<String>) -> some View {
        let fullYear = model.family == .large
        let weeks = fullYear ? 53 : max(5, min(53, Int((model.size.dimensions.width - 28) / 14)))
        let today = Date()
        let calendar = Calendar.current
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: today) - 1
        let count = weeks * 7 - (6 - weekday)
        let days = (0..<count).map { index -> GitHubService.Day in
            let day = calendar.date(byAdding: .day, value: index - count + 1, to: today) ?? today
            let wrote = dates.contains(key(day))
            return GitHubService.Day(date: key(day), count: wrote ? 1 : 0, level: wrote ? 4 : 0)
        }
        let year = String(key(today).prefix(4))
        let thisYear = dates.filter { $0.hasPrefix(year) }.count
        return VStack(alignment: .leading, spacing: 8) {
            SlateHeader(title: model.family == .large ? "Daily notes" : "Streak") {
                Text("🔥 \(streak(dates))").font(.system(size: 12, weight: .semibold)).help("Days in a row with a daily note")
            }
            ContributionGrid(days: days, weeks: weeks, color: { [accent] in $0 > 0 ? accent : Color.primary.opacity(0.1) }, wraps: fullYear)
                .frame(maxHeight: fullYear ? .infinity : nil)
            if fullYear {
                HStack {
                    stat("This year", "\(thisYear)")
                    stat("Streak", "\(streak(dates)) days")
                    stat("All time", "\(dates.count)")
                }
            } else {
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open(todayPath) }
        .widgetPadding()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 16, weight: .bold, design: .rounded))
            Text(label).font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

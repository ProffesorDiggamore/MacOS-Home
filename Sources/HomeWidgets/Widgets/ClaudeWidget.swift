import SwiftUI

enum ClaudeKeys {
    static let showUsage = ConfigKey("showUsage", true)
    static let showIdle = ConfigKey("showIdle", true)
    static let display = ConfigKey("display", ClaudeDisplay.sessions)
}

enum ClaudeDisplay: String, ConfigOption {
    case sessions, mascot

    var label: String {
        switch self {
        case .sessions: return "Session List"
        case .mascot: return "Just the Crab"
        }
    }
}

struct ClaudeWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var claude = ClaudeMonitor.shared

    private var sessions: [ClaudeMonitor.Session] {
        model[ClaudeKeys.showIdle] ? claude.sessions : claude.sessions.filter { $0.state != .idle }
    }

    var body: some View {
        if model[ClaudeKeys.display] == .mascot {
            ClaudeMascotView(model: model)
        } else {
            sessionList
        }
    }

    private var sessionList: some View {
        Ticking(everySecond: false) { now in
            Group {
                if !claude.isInstalled {
                    WidgetMessage(symbol: "terminal",
                                  title: "Claude Code not found",
                                  detail: "Install Claude Code and run `claude` in Terminal. Sessions will show up here.")
                } else {
                    switch model.family {
                    case .small: small(now)
                    case .medium: list(now, limit: 3)
                    case .large: list(now, limit: 7)
                    }
                }
            }
        }
        .monitoring(ClaudeMonitor.shared)
    }

    private var header: some View {
        HStack(spacing: 6) {
            ClaudeMark()
                .fill(Palette.claude)
                .frame(width: 15, height: 15)
            Text("Claude Code")
                .font(.system(size: 12.5, weight: .semibold))
            Spacer(minLength: 4)
            if claude.workingCount > 0 {
                Text("\(claude.workingCount) working")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Palette.claude)
            }
            if claude.waitingCount > 0 {
                Text("\(claude.waitingCount) waiting")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.green)
            }
        }
    }

    private func small(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                ClaudeMark().fill(Palette.claude).frame(width: 16, height: 16)
                Text("Claude").font(.system(size: 12.5, weight: .semibold))
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(claude.activeCount)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                Text(claude.activeCount == 1 ? "session" : "sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let latest = sessions.first {
                HStack(spacing: 5) {
                    StatusDot(state: latest.state)
                    Text(latest.projectName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                Text(latest.state == .idle ? Fmt.ago(latest.lastActivity, now: now) : latest.state.label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(claude.hasLoaded ? "No sessions yet" : "Looking…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if let latest = sessions.first { claude.open(latest) }
        }
        .widgetPadding()
    }

    private func list(_ now: Date, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if sessions.isEmpty {
                Spacer(minLength: 0)
                Text(claude.hasLoaded ? "No recent sessions. Start one with `claude` in Terminal." : "Looking for sessions…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                ForEach(sessions.prefix(limit)) { session in
                    ClaudeSessionRow(session: session, now: now, detailed: model.family == .large)
                }
            }
            Spacer(minLength: 0)
            if model.family == .large && model[ClaudeKeys.showUsage] {
                Divider().opacity(0.5)
                usageFooter
            }
        }
        .widgetPadding()
    }

    private var usageFooter: some View {
        HStack(spacing: 14) {
            usageStat("Tokens today", Fmt.count(claude.usageToday.total))
            usageStat("Output", Fmt.count(claude.usageToday.output))
            usageStat("Replies", Fmt.count(claude.usageToday.messages))
            usageStat("Sessions", "\(claude.sessionsToday)")
        }
    }

    private func usageStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClaudeSessionRow: View {
    let session: ClaudeMonitor.Session
    let now: Date
    var detailed = false
    @State private var hovering = false

    private var statusColor: Color {
        switch session.state {
        case .working: return Palette.claude
        case .waiting: return .green
        case .idle: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StatusDot(state: session.state)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(session.projectName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if detailed, let branch = session.branch {
                        Text(branch)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                            .lineLimit(1)
                    }
                }
                Text(session.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if detailed, session.state == .waiting, let reply = session.lastReply {
                    Text(reply)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(session.state == .idle ? Fmt.ago(session.lastActivity, now: now) : session.state.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                if detailed, let model = session.model {
                    Text(model)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { ClaudeMonitor.shared.open(session) }
        .help(session.state == .idle ? "Resume this session in Terminal" : "Show the terminal running this session")
        .contextMenu {
            if session.state != .idle {
                Button("Show Terminal") { ClaudeMonitor.shared.open(session) }
            }
            Button("Resume in New Terminal Window") { ClaudeMonitor.shared.resume(session) }
            Button("New Session in “\(session.projectName)”") { ClaudeMonitor.shared.newSession(in: session.projectPath) }
            Divider()
            Button("Open Project Folder") { ClaudeMonitor.shared.revealProject(session) }
            Button("Copy Session ID") { ClaudeMonitor.shared.copySessionID(session) }
        }
    }
}

// MARK: - Session Budget

enum SessionBudgetKeys {
    static let perWeek = ConfigKey("perWeek", 10)
    /// Calendar weekday the week starts on (1 is Sunday): the day the weekly limit resets.
    static let resetDay = ConfigKey("resetDay", 2)
    /// When each logged session started, in ISO 8601.
    static let log = ConfigKey("log", [String]())
}

/// A weekly budget of 5-hour Claude Code windows, spread evenly over the days left in the week.
struct SessionBudget {
    static let window: TimeInterval = 5 * 3600
    private static let iso = ISO8601DateFormatter()

    let perWeek: Int
    let weekStart: Date
    let weekEnd: Date
    /// This week's sessions, oldest first.
    let sessions: [Date]
    let now: Date

    init(perWeek: Int, resetDay: Int, log: [String], now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let back = (calendar.component(.weekday, from: today) - resetDay + 7) % 7
        let start = calendar.date(byAdding: .day, value: -back, to: today) ?? today
        self.perWeek = max(1, perWeek)
        self.weekStart = start
        self.weekEnd = calendar.date(byAdding: .day, value: 7, to: start) ?? today
        self.sessions = log.compactMap { Self.iso.date(from: $0) }.filter { $0 >= start }.sorted()
        self.now = now
    }

    var used: Int { sessions.count }
    var left: Int { max(0, perWeek - used) }
    var usedToday: Int { sessions.filter { Calendar.current.isDate($0, inSameDayAs: now) }.count }

    /// Days left in the week, counting today.
    var daysLeft: Int {
        let today = Calendar.current.startOfDay(for: now)
        return max(1, Calendar.current.dateComponents([.day], from: today, to: weekEnd).day ?? 1)
    }

    /// Today's fair share, worked out from the start of the day so logging a session doesn't move it.
    var todayShare: Double { Double(max(0, perWeek - (used - usedToday))) / Double(daysLeft) }

    /// When the window from the latest session runs out, if it's still going.
    var windowEnds: Date? {
        guard let last = sessions.last else { return nil }
        let end = last.addingTimeInterval(Self.window)
        return end > now ? end : nil
    }

    /// Sessions per day of the week, starting on the reset day.
    var perDay: [Int] {
        let calendar = Calendar.current
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return 0 }
            return sessions.filter { calendar.isDate($0, inSameDayAs: day) }.count
        }
    }

    var status: (text: String, color: Color) {
        if left == 0 { return ("Out until \(DateFormats.string(weekEnd, format: "EEE"))", .red) }
        let today = Double(usedToday)
        if today > todayShare + 0.05 { return ("Over today's share", .orange) }
        if usedToday > 0 && todayShare - today < 1 { return ("Done for today", .green) }
        return ("On pace", .green)
    }

    /// A session count with at most one decimal: 2, 1.4.
    static func amount(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }

    static func adding(_ date: Date, to log: [String], weekStart: Date) -> [String] {
        log.filter { (iso.date(from: $0) ?? .distantPast) >= weekStart } + [iso.string(from: date)]
    }

    /// A believable week for the gallery: a heavy start, then one a day, with a window running now.
    static func sample(resetDay: Int, now: Date) -> [String] {
        let calendar = Calendar.current
        let start = SessionBudget(perWeek: 1, resetDay: resetDay, log: [], now: now).weekStart
        let today = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: now)).day ?? 0
        var dates = [now.addingTimeInterval(-2 * 3600)]
        for day in 0..<today {
            for session in 0..<(day == 0 ? 3 : day == 1 ? 2 : 1) {
                dates.append(start.addingTimeInterval(Double(day) * 86_400 + Double(9 + session * 5) * 3600))
            }
        }
        return dates.sorted().map { iso.string(from: $0) }
    }
}

/// Click it each time you start a 5-hour Claude Code window; it tells you how many you can spend today.
struct SessionBudgetWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private func budget(_ now: Date) -> SessionBudget {
        let resetDay = model[SessionBudgetKeys.resetDay]
        let log = context == .gallery ? SessionBudget.sample(resetDay: resetDay, now: now) : model[SessionBudgetKeys.log]
        return SessionBudget(perWeek: model[SessionBudgetKeys.perWeek], resetDay: resetDay, log: log, now: now)
    }

    private func logSession() {
        let now = Date()
        model.config[SessionBudgetKeys.log] = SessionBudget.adding(now, to: model[SessionBudgetKeys.log], weekStart: budget(now).weekStart)
    }

    private func undo() {
        var log = model[SessionBudgetKeys.log]
        guard !log.isEmpty else { return }
        log.removeLast()
        model.config[SessionBudgetKeys.log] = log
    }

    var body: some View {
        Ticking(everySecond: false) { now in
            let budget = budget(now)
            ZStack(alignment: .topTrailing) {
                Button(action: logSession) {
                    Group {
                        if model.family == .small { small(budget) } else { medium(budget) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .widgetPadding()
                }
                .buttonStyle(WidgetButtonStyle())
                .help("Log a 5-hour Claude Code session")
                if budget.used > 0 {
                    Button(action: undo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 22)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(WidgetButtonStyle())
                    .help("Undo the last session")
                    .padding(10)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            ClaudeMark().fill(Palette.claude).frame(width: 15, height: 15)
            Text("Sessions").font(.system(size: 12.5, weight: .semibold))
        }
    }

    private func todayLine(_ budget: SessionBudget) -> some View {
        Text("Today \(budget.usedToday) of \(SessionBudget.amount(budget.todayShare))")
            .font(.system(size: 11.5, weight: .semibold))
            .monospacedDigit()
    }

    private func statusLine(_ budget: SessionBudget, showsEnd: Bool = true) -> some View {
        let status = budget.status
        return HStack(spacing: 4) {
            Circle().fill(status.color).frame(width: 6, height: 6)
            Text(status.text).foregroundStyle(status.color)
            if showsEnd, let end = budget.windowEnds {
                Text("· ends \(DateFormats.string(end, format: "h:mm a"))").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(1)
    }

    private func small(_ budget: SessionBudget) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            header
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(budget.left)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("/ \(budget.perWeek) left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            todayLine(budget)
            statusLine(budget, showsEnd: false)
        }
    }

    private func medium(_ budget: SessionBudget) -> some View {
        HStack(spacing: 16) {
            RingGauge(value: Double(budget.used) / Double(budget.perWeek), color: Palette.claude, lineWidth: 9) {
                VStack(spacing: -2) {
                    Text("\(budget.left)")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("left").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
            .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                header
                Text("\(SessionBudget.amount(budget.todayShare)) a day · \(budget.daysLeft) \(budget.daysLeft == 1 ? "day" : "days") left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                weekStrip(budget)
                Spacer(minLength: 0)
                todayLine(budget)
                statusLine(budget)
            }
        }
    }

    private func weekStrip(_ budget: SessionBudget) -> some View {
        let counts = budget.perDay
        let tallest = Double(max(2, counts.max() ?? 0))
        let todayIndex = 7 - budget.daysLeft
        let letters = Calendar.current.veryShortWeekdaySymbols
        let firstDay = Calendar.current.component(.weekday, from: budget.weekStart) - 1
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 3) {
                    ZStack(alignment: .bottom) {
                        Capsule().fill(Color.primary.opacity(0.08))
                        if counts[index] > 0 {
                            Capsule().fill(style.tone(Palette.claude))
                                .frame(height: max(5, 26 * Double(counts[index]) / tallest))
                        }
                    }
                    .frame(width: 9, height: 26)
                    Text(letters[(firstDay + index) % 7])
                        .font(.system(size: 9, weight: index == todayIndex ? .bold : .medium))
                        .foregroundStyle(index == todayIndex ? Color.primary : Color.secondary)
                }
            }
        }
    }
}

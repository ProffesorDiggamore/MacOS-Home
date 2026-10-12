import SwiftUI
import AppKit

// MARK: - To-do list

enum TodoKeys {
    /// Each entry is "0|text" (open) or "1|text" (done).
    static let items = ConfigKey<[String]>("items", ["0|Finish homework", "0|Clean my room", "1|Read Psalm 23"])
}

struct TodoWidget: View {
    @ObservedObject var model: WidgetModel
    @State private var draft = ""
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetStyle) private var style

    private var items: [(done: Bool, text: String)] {
        model[TodoKeys.items].map { entry in
            let done = entry.hasPrefix("1|")
            let text = entry.count > 2 ? String(entry.dropFirst(2)) : entry
            return (done, text)
        }
    }

    private func save(_ list: [(done: Bool, text: String)]) {
        model.config[TodoKeys.items] = list.map { ($0.done ? "1|" : "0|") + $0.text }
    }

    var body: some View {
        let list = items
        let limit = model.family == .large ? 11 : (model.family == .medium ? 4 : 4)
        let open = list.filter { !$0.done }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("To-Do").font(.system(size: 13, weight: .bold)).foregroundStyle(style.tone(accent))
                Spacer()
                Text(open == 0 ? "All done" : "\(open) left").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                if list.contains(where: \.done) {
                    Button {
                        save(list.filter { !$0.done })
                    } label: {
                        Image(systemName: "trash").font(.system(size: 10))
                    }
                    .buttonStyle(WidgetButtonStyle())
                    .help("Clear completed")
                }
            }
            ForEach(Array(list.enumerated().prefix(limit)), id: \.offset) { index, item in
                HStack(spacing: 7) {
                    Button {
                        var updated = list
                        updated[index].done.toggle()
                        save(updated)
                    } label: {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(item.done ? style.tone(accent) : Color.secondary)
                    }
                    .buttonStyle(WidgetButtonStyle())
                    Text(item.text)
                        .font(.system(size: 12.5))
                        .strikethrough(item.done)
                        .foregroundStyle(item.done ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contextMenu {
                    Button("Delete") {
                        var updated = list
                        updated.remove(at: index)
                        save(updated)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                TextField("Add a task", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        save(list + [(false, text)])
                        draft = ""
                    }
            }
        }
        .widgetPadding()
    }
}

// MARK: - Habits

enum HabitKeys {
    static let habits = ConfigKey<[String]>("habits", ["Read the Bible", "Exercise", "Drink water", "Practice guitar"])
    /// "habit|yyyy-MM-dd" for each day a habit was done.
    static let log = ConfigKey<[String]>("log", [])
}

struct HabitsWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    private static func dayKey(_ date: Date) -> String {
        DateFormats.string(date, format: "yyyy-MM-dd")
    }

    private func streak(_ habit: String, log: Set<String>, today: Date) -> Int {
        var count = 0
        var day = today
        let calendar = Calendar.current
        if !log.contains("\(habit)|\(Self.dayKey(day))") {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while log.contains("\(habit)|\(Self.dayKey(day))") {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    private func toggle(_ habit: String, _ day: Date) {
        var log = model[HabitKeys.log]
        let key = "\(habit)|\(Self.dayKey(day))"
        if let index = log.firstIndex(of: key) { log.remove(at: index) } else { log.append(key) }
        // Keep the log from growing forever (about a year per habit).
        model.config[HabitKeys.log] = Array(log.suffix(2000))
    }

    var body: some View {
        Ticking(everySecond: false) { now in
            content(now)
        }
    }

    @ViewBuilder
    private func content(_ now: Date) -> some View {
        let habits = model[HabitKeys.habits]
        let log = Set(model[HabitKeys.log])
        let dayCount = model.family == .large ? 10 : 7
        let calendar = Calendar.current
        let days = (0..<dayCount).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: now) }
        VStack(alignment: .leading, spacing: model.family == .large ? 10 : 7) {
            HStack {
                Image(systemName: "flame.fill").foregroundStyle(style.tone(.orange))
                Text("Habits").font(.system(size: 13, weight: .bold))
                Spacer()
                ForEach(days, id: \.self) { day in
                    Text(DateFormats.string(day, template: "EEEEE"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(calendar.isDateInToday(day) ? Color.primary : Color.secondary)
                        .frame(width: 15)
                }
                Color.clear.frame(width: 28, height: 1)
            }
            ForEach(habits.prefix(model.family == .large ? 9 : 4), id: \.self) { habit in
                HStack(spacing: 0) {
                    Text(habit).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 6)
                    ForEach(days, id: \.self) { day in
                        let done = log.contains("\(habit)|\(Self.dayKey(day))")
                        Button {
                            toggle(habit, day)
                        } label: {
                            Circle()
                                .fill(done ? style.tone(.orange) : Color.primary.opacity(0.1))
                                .frame(width: 13, height: 13)
                                .overlay(Circle().stroke(Color.primary.opacity(calendar.isDateInToday(day) ? 0.35 : 0), lineWidth: 1))
                                .frame(width: 15)
                        }
                        .buttonStyle(WidgetButtonStyle())
                    }
                    Text("\(streak(habit, log: log, today: now))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }
}

// MARK: - Quick links

enum LinkKeys {
    /// "Title|https://…"
    static let links = ConfigKey<[String]>("links", [
        "YouTube|https://youtube.com", "Claude|https://claude.ai", "GitHub|https://github.com",
        "Bible|https://www.biblegateway.com", "Gmail|https://mail.google.com", "Classroom|https://classroom.google.com",
        "Spotify|https://open.spotify.com", "Maps|https://maps.apple.com",
    ])
}

struct LinksWidget: View {
    @ObservedObject var model: WidgetModel

    private var links: [(title: String, url: URL)] {
        model[LinkKeys.links].compactMap { entry in
            let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
            let raw = parts.count == 2 ? parts[1] : parts[0]
            let address = raw.contains("://") ? raw : "https://" + raw
            guard let url = URL(string: address) else { return nil }
            let title = parts.count == 2 ? parts[0] : (url.host ?? raw)
            return (title, url)
        }
    }

    var body: some View {
        let columns = max(1, Int((model.size.dimensions.width - 16) / 72))
        let rows = max(1, Int((model.size.dimensions.height - 20) / 66))
        let visible = Array(links.prefix(columns * rows))
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < visible.count {
                            LinkTile(title: visible[index].title, url: visible[index].url)
                        } else {
                            Color.clear.frame(width: 1, height: 1)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetPadding(12)
    }
}

private struct LinkTile: View {
    let title: String
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            VStack(spacing: 4) {
                AsyncImage(url: URL(string: "https://icons.duckduckgo.com/ip3/\(url.host ?? "").ico")) { image in
                    image.resizable().interpolation(.high).scaledToFit().padding(8)
                } placeholder: {
                    Text(String(title.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(WidgetButtonStyle())
        .help(url.absoluteString)
    }
}

// MARK: - Calculator

final class CalculatorState: ObservableObject {
    @Published var display = "0"
    private var accumulator: Double?
    private var pending: String?
    private var startNew = true

    private var value: Double { Double(display) ?? 0 }

    private func show(_ number: Double) {
        if number.isNaN || number.isInfinite {
            display = "Error"
        } else if number == number.rounded() && abs(number) < 1e15 {
            display = String(format: "%.0f", number)
        } else {
            display = String(format: "%.10g", number)
        }
        startNew = true
    }

    func press(_ key: String) {
        switch key {
        case "0"..."9":
            if startNew || display == "0" || display == "Error" { display = key } else if display.count < 14 { display += key }
            startNew = false
        case ".":
            if startNew { display = "0."; startNew = false } else if !display.contains(".") { display += "." }
        case "AC":
            display = "0"; accumulator = nil; pending = nil; startNew = true
        case "±":
            if display != "0" { display = display.hasPrefix("-") ? String(display.dropFirst()) : "-" + display }
        case "%":
            show(value / 100)
        case "+", "−", "×", "÷":
            if let pending, let accumulator, !startNew { show(apply(pending, accumulator, value)) }
            accumulator = value
            pending = key
            startNew = true
        case "=":
            if let pending, let accumulator { show(apply(pending, accumulator, value)) }
            pending = nil
            accumulator = nil
        default:
            break
        }
    }

    private func apply(_ op: String, _ a: Double, _ b: Double) -> Double {
        switch op {
        case "+": return a + b
        case "−": return a - b
        case "×": return a * b
        case "÷": return b == 0 ? .nan : a / b
        default: return b
        }
    }
}

struct CalculatorWidget: View {
    @ObservedObject var model: WidgetModel
    @StateObject private var calc = CalculatorState()

    private let rows: [[String]] = [
        ["AC", "±", "%", "÷"],
        ["7", "8", "9", "×"],
        ["4", "5", "6", "−"],
        ["1", "2", "3", "+"],
        ["0", ".", "="],
    ]

    var body: some View {
        let large = model.family == .large
        let spacing: CGFloat = large ? 8 : 4
        VStack(alignment: .trailing, spacing: spacing) {
            Text(calc.display)
                .font(.system(size: large ? 44 : 22, weight: .light, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(row, id: \.self) { key in
                        Button { calc.press(key) } label: {
                            Text(key)
                                .font(.system(size: large ? 20 : 12, weight: .medium, design: .rounded))
                                .foregroundStyle(["÷", "×", "−", "+", "="].contains(key) ? Color.white : Color.primary)
                                .frame(maxWidth: key == "0" ? .infinity : nil)
                                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                                .background(
                                    Capsule().fill(["÷", "×", "−", "+", "="].contains(key) ? Color.orange : Color.primary.opacity(["AC", "±", "%"].contains(key) ? 0.18 : 0.09))
                                )
                        }
                        .buttonStyle(WidgetButtonStyle())
                        .layoutPriority(key == "0" ? 2 : 1)
                    }
                }
            }
        }
        .padding(large ? 16 : 10)
    }
}

// MARK: - Stopwatch

final class StopwatchState: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var laps: [TimeInterval] = []
    private var started: Date?
    private var accumulated: TimeInterval = 0

    func elapsed(at date: Date = Date()) -> TimeInterval {
        accumulated + (started.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggle() {
        if isRunning {
            accumulated = elapsed()
            started = nil
        } else {
            started = Date()
        }
        isRunning.toggle()
    }

    func lapOrReset() {
        if isRunning {
            laps.insert(elapsed(), at: 0)
        } else {
            accumulated = 0
            laps = []
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        let hundredths = Int((interval * 100).rounded(.down))
        let minutes = hundredths / 6000
        let seconds = (hundredths / 100) % 60
        let fraction = hundredths % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, fraction)
    }
}

struct StopwatchWidget: View {
    @ObservedObject var model: WidgetModel
    @StateObject private var watch = StopwatchState()
    @Environment(\.widgetIsVisible) private var visible

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05, paused: !watch.isRunning || !visible)) { timeline in
            let elapsed = watch.elapsed(at: timeline.date)
            HStack(spacing: 14) {
                VStack(spacing: 10) {
                    Text(StopwatchState.format(elapsed))
                        .font(.system(size: model.family == .small ? 28 : 34, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    HStack(spacing: 12) {
                        Button(action: watch.lapOrReset) {
                            Text(watch.isRunning ? "Lap" : "Reset")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 54, height: 30)
                                .background(Capsule().fill(Color.primary.opacity(0.12)))
                        }
                        Button(action: watch.toggle) {
                            Text(watch.isRunning ? "Stop" : "Start")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(watch.isRunning ? Color.red : Color.green)
                                .frame(width: 54, height: 30)
                                .background(Capsule().fill((watch.isRunning ? Color.red : Color.green).opacity(0.18)))
                        }
                    }
                    .buttonStyle(WidgetButtonStyle())
                }
                if model.family == .medium {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Laps").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        ForEach(Array(watch.laps.prefix(5).enumerated()), id: \.offset) { index, lap in
                            HStack {
                                Text("Lap \(watch.laps.count - index)").font(.system(size: 11))
                                Spacer()
                                Text(StopwatchState.format(lap)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .widgetPadding()
        }
    }
}

// MARK: - Counter

enum CounterKeys {
    static let count = ConfigKey("count", 0)
    static let title = ConfigKey("title", "Glasses of water")
    static let goal = ConfigKey("goal", 8)
    static let resetsDaily = ConfigKey("resetsDaily", true)
    static let day = ConfigKey("day", "")
}

struct CounterWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetStyle) private var style

    private var count: Int {
        if model[CounterKeys.resetsDaily] && model[CounterKeys.day] != DateFormats.string(Date(), format: "yyyy-MM-dd") {
            return 0
        }
        return model[CounterKeys.count]
    }

    private func change(_ delta: Int) {
        model.config[CounterKeys.count] = max(0, count + delta)
        model.config[CounterKeys.day] = DateFormats.string(Date(), format: "yyyy-MM-dd")
    }

    var body: some View {
        let goal = model[CounterKeys.goal]
        let tone = style.tone(accent)
        let progress = goal > 0 ? Double(count) / Double(goal) : 0
        HStack(spacing: 16) {
            if model.family == .medium && goal > 0 {
                RingGauge(value: progress, color: accent, lineWidth: 9) {
                    Text(progress >= 1 ? "🎉" : Fmt.percent(progress))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                .frame(width: 100, height: 100)
            }
            VStack(spacing: 6) {
                Text(model[CounterKeys.title])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    + Text(goal > 0 ? " / \(goal)" : "")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                HStack(spacing: 14) {
                    Button { change(-1) } label: {
                        Image(systemName: "minus").font(.system(size: 14, weight: .bold))
                            .frame(width: 38, height: 30)
                            .background(Capsule().fill(Color.primary.opacity(0.1)))
                    }
                    Button { change(1) } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 38, height: 30)
                            .background(Capsule().fill(tone == .white ? Color.white.opacity(0.3) : accent))
                    }
                }
                .buttonStyle(WidgetButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
        .widgetPadding()
    }
}

// MARK: - Sun

enum SunKeys {
    static let city = ConfigKey("city", "")
}

struct SunArcWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var store = WeatherStore.shared
    @Environment(\.widgetContext) private var context

    private var key: String { WeatherStore.key(forCity: model[SunKeys.city]) }

    private var times: (rise: Date, set: Date, place: String)? {
        if context == .gallery {
            let start = Calendar.current.startOfDay(for: Date())
            return (start.addingTimeInterval(7 * 3600 + 20 * 60), start.addingTimeInterval(18 * 3600 + 50 * 60), "Cupertino")
        }
        guard let report = store.reports[key], let rise = report.sunrise, let set = report.sunset else { return nil }
        return (rise, set, report.place)
    }

    var body: some View {
        Ticking(everySecond: false) { now in
            if let times {
                arc(now: now, rise: times.rise, set: times.set, place: times.place)
            } else if let error = store.errors[key] {
                WidgetMessage(symbol: "sun.horizon", title: "Sun times unavailable", detail: error)
            } else {
                WidgetMessage(symbol: "sun.horizon", title: "Finding the sun…")
            }
        }
        .onAppear { if context != .gallery { store.retain(key) } }
        .onDisappear { if context != .gallery { store.release(key) } }
    }

    private func arc(now: Date, rise: Date, set: Date, place: String) -> some View {
        let total = set.timeIntervalSince(rise)
        let progress = min(1, max(0, now.timeIntervalSince(rise) / max(total, 1)))
        let isDay = now >= rise && now <= set
        let remaining = isDay ? set.timeIntervalSince(now) : (now < rise ? rise.timeIntervalSince(now) : rise.addingTimeInterval(86400).timeIntervalSince(now))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(place).font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(isDay ? "\(Fmt.duration(minutes: Int(remaining / 60))) of daylight left" : "Sunrise in \(Fmt.duration(minutes: Int(remaining / 60)))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Canvas { canvas, size in
                let baseline = size.height - 6
                let radiusX = size.width / 2 - 12
                let radiusY = size.height - 16
                let center = CGPoint(x: size.width / 2, y: baseline)
                var path = Path()
                for step in 0...60 {
                    let t = Double(step) / 60
                    let point = CGPoint(x: center.x - radiusX * CGFloat(cos(t * .pi)), y: center.y - radiusY * CGFloat(sin(t * .pi)))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                canvas.stroke(path, with: .color(.secondary.opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                var horizon = Path()
                horizon.move(to: CGPoint(x: 4, y: baseline))
                horizon.addLine(to: CGPoint(x: size.width - 4, y: baseline))
                canvas.stroke(horizon, with: .color(.secondary.opacity(0.4)), lineWidth: 1)
                let t = isDay ? progress : (now < rise ? 0 : 1)
                let sun = CGPoint(x: center.x - radiusX * CGFloat(cos(t * .pi)), y: center.y - radiusY * CGFloat(sin(t * .pi)))
                let glow = CGRect(x: sun.x - 14, y: sun.y - 14, width: 28, height: 28)
                canvas.fill(Path(ellipseIn: glow), with: .color(.yellow.opacity(isDay ? 0.3 : 0.1)))
                canvas.fill(Path(ellipseIn: glow.insetBy(dx: 7, dy: 7)), with: .color(isDay ? .yellow : .gray))
            }
            HStack {
                Label(DateFormats.shortTime(rise), systemImage: "sunrise.fill")
                Spacer()
                Label(DateFormats.shortTime(set), systemImage: "sunset.fill")
            }
            .font(.system(size: 11, weight: .medium))
            .symbolRenderingMode(.multicolor)
        }
        .widgetPadding()
    }
}

// MARK: - Clipboard

struct ClipboardWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var clipboard = ClipboardMonitor.shared
    @Environment(\.widgetContext) private var context

    private var clips: [ClipboardMonitor.Clip] {
        if context == .gallery {
            return ["git push -u origin main", "https://claude.ai", "Meet at 7 by the gym doors", "#D97757"]
                .map { ClipboardMonitor.Clip(text: $0, date: Date()) }
        }
        return clipboard.clips
    }

    var body: some View {
        Ticking(everySecond: false) { now in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard.fill").foregroundStyle(Color.indigo)
                    Text("Clipboard").font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button {
                        clipboard.isPaused.toggle()
                    } label: {
                        Image(systemName: clipboard.isPaused ? "play.circle" : "pause.circle")
                    }
                    .buttonStyle(WidgetButtonStyle())
                    .help(clipboard.isPaused ? "Resume recording" : "Pause recording")
                    Button {
                        clipboard.clear()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(WidgetButtonStyle())
                    .help("Clear history")
                }
                .font(.system(size: 12))
                if clips.isEmpty {
                    Spacer(minLength: 0)
                    Text(clipboard.isPaused ? "Paused" : "Copy some text and it'll show up here.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(clips.prefix(model.family == .large ? 10 : 4)) { clip in
                        Button {
                            clipboard.copy(clip)
                        } label: {
                            HStack {
                                Text(clip.text.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 12, design: .monospaced))
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(Fmt.ago(clip.date, now: now)).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                        }
                        .buttonStyle(WidgetButtonStyle())
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetPadding()
        }
        .monitoring(if: context != .gallery, ClipboardMonitor.shared)
    }
}

// MARK: - Volume

struct VolumeWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var volume = VolumeMonitor.shared
    @Environment(\.widgetStyle) private var style

    private var symbol: String {
        if volume.isMuted || volume.volume == 0 { return "speaker.slash.fill" }
        if volume.volume < 0.34 { return "speaker.wave.1.fill" }
        if volume.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        let level = Binding(get: { volume.volume }, set: { volume.set($0) })
        VStack(spacing: 10) {
            HStack {
                Button(action: volume.toggleMute) {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(style.tone(.pink))
                        .frame(width: 34)
                }
                .buttonStyle(WidgetButtonStyle())
                Spacer()
                Text(volume.isMuted ? "Muted" : Fmt.percent(volume.volume))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Slider(value: level, in: 0...1)
                .controlSize(.small)
            HStack(spacing: 10) {
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { preset in
                    Button {
                        volume.set(preset)
                    } label: {
                        Text(Fmt.percent(preset))
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.primary.opacity(0.08)))
                    }
                    .buttonStyle(WidgetButtonStyle())
                }
            }
            .opacity(model.family == .medium ? 1 : 0)
            .frame(height: model.family == .medium ? nil : 0)
        }
        .widgetPadding(16)
        .monitoring(VolumeMonitor.shared)
    }
}

// MARK: - Wi-Fi

struct WiFiWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var wifi = WiFiMonitor.shared
    @Environment(\.widgetStyle) private var style

    private var symbol: String {
        switch wifi.bars {
        case 0: return "wifi.slash"
        case 1: return "wifi.exclamationmark"
        default: return "wifi"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: symbol, variableValue: Double(wifi.bars) / 4)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(style.tone(.blue))
                Spacer(minLength: 0)
                Text(wifi.networkName ?? (wifi.isOn ? "Wi-Fi" : "Wi-Fi Off"))
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(wifi.quality).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary)
                if wifi.isOn && wifi.rssi != 0 {
                    Text("\(wifi.rssi) dBm · \(Int(wifi.transmitRate)) Mbps")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if model.family == .medium {
                VStack(alignment: .leading, spacing: 6) {
                    Sparkline(values: wifi.history.values, color: .blue, capacity: 40)
                    if let channel = wifi.channel {
                        Text("Channel \(channel)\(wifi.band.map { " · " + $0 } ?? "")")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Text("Noise \(wifi.noise) dBm").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetPadding()
        .monitoring(WiFiMonitor.shared)
    }
}

// MARK: - Disk activity

struct DiskActivityWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var disk = DiskActivityMonitor.shared

    private var peak: Double { max(disk.readHistory.peak, disk.writeHistory.peak, 1_000_000) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Disk Activity", symbol: "internaldrive", color: .orange)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Read").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    Text(Fmt.rate(disk.readRate)).font(.system(size: model.family == .small ? 15 : 19, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Write").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    Text(Fmt.rate(disk.writeRate)).font(.system(size: model.family == .small ? 15 : 19, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
            ZStack {
                Sparkline(values: disk.readHistory.values, color: .blue, maxValue: peak)
                Sparkline(values: disk.writeHistory.values, color: .orange, maxValue: peak, lineWidth: 1.2)
            }
            .frame(maxHeight: .infinity)
        }
        .widgetPadding()
        .monitoring(DiskActivityMonitor.shared)
    }
}

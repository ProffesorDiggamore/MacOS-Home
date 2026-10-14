import SwiftUI
import AppKit

// Planning widgets: a month calendar, what's up next, the week ahead,
// a class schedule, homework, and a Bible reading plan.

private let sampleEvents: [EventService.Event] = {
    let now = Date()
    let calendar = Calendar.current
    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? now
    }
    return [
        .init(id: "1", title: "Team standup", start: now.addingTimeInterval(25 * 60), end: now.addingTimeInterval(40 * 60), isAllDay: false,
              color: .blue, location: nil, calendarName: "Work", joinURL: URL(string: "https://meet.google.com/abc")),
        .init(id: "2", title: "Basketball practice", start: at(0, 17), end: at(0, 18, 30), isAllDay: false, color: .orange, location: "Gym"),
        .init(id: "3", title: "Bible study", start: at(1, 19), end: at(1, 20), isAllDay: false, color: .purple, location: nil),
        .init(id: "4", title: "Math test", start: at(2, 9), end: at(2, 10), isAllDay: false, color: .red, location: "Room 204"),
        .init(id: "5", title: "Mom's birthday", start: at(3, 0), end: at(4, 0), isAllDay: true, color: .pink, location: nil),
    ]
}()

/// Holds Calendar access while the widget shows, and supplies sample events in the gallery.
private struct EventsSource: ViewModifier {
    @Environment(\.widgetContext) private var context
    func body(content: Content) -> some View {
        content
            .onAppear { if context == .desktop { EventService.shared.retainEvents() } }
            .onDisappear { if context == .desktop { EventService.shared.releaseEvents() } }
    }
}

private extension View {
    func usesEvents() -> some View { modifier(EventsSource()) }
}

private func accessMessage(_ access: EventService.Access) -> String? {
    switch access {
    case .denied: return "Allow Calendar access in System Settings › Privacy › Calendars."
    case .unavailable: return "Install the app (make install) to show your calendar."
    default: return nil
    }
}

// MARK: - Month calendar

struct MonthCalendarWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = EventService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetAccent) private var accent
    @State private var offset = 0
    @State private var busy: [Int: [Color]] = [:]

    var body: some View {
        let calendar = Calendar.current
        let today = Date()
        let month = calendar.date(byAdding: .month, value: offset, to: today) ?? today
        let interval = calendar.dateInterval(of: .month, for: month)!
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let days = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        let isThisMonth = offset == 0
        let todayNumber = calendar.component(.day, from: today)
        // One-row-tall widgets (small, medium, wide) use the compact grid so all six weeks fit.
        let compact = model.size.cells.rows == 1
        let big = model.family == .large
        let tone = style.tone(.red)
        let cells = leading + days
        let weeks = (cells + 6) / 7

        VStack(spacing: compact ? 3 : 5) {
            HStack {
                Text(DateFormats.string(month, template: compact ? "MMMM" : "MMMMyyyy").uppercased())
                    .font(.system(size: compact ? 10.5 : 12, weight: .bold))
                    .foregroundStyle(tone)
                Spacer()
                if model.family != .small {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left") }
                    Button { offset = 0 } label: { Image(systemName: "circle.fill").font(.system(size: 5)) }.disabled(offset == 0)
                    Button { offset += 1 } label: { Image(systemName: "chevron.right") }
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(WidgetButtonStyle())
            HStack(spacing: 0) {
                ForEach(ordered.indices, id: \.self) { index in
                    Text(ordered[index])
                        .font(.system(size: compact ? 8.5 : (big ? 11.5 : 10), weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            // Week rows share the height, so the month fills tall and large widgets.
            ForEach(0..<weeks, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let slot = week * 7 + column
                        if slot < leading || slot >= cells {
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        } else {
                            dayCell(slot - leading + 1, isToday: isThisMonth && slot - leading + 1 == todayNumber,
                                    compact: compact, big: big, tone: tone)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(maxHeight: compact ? nil : .infinity)
            }
            if compact { Spacer(minLength: 0) }
        }
        .widgetPadding(compact ? 12 : 14)
        .usesEvents()
        .task(id: "\(offset)-\(service.events.count)-\(service.eventAccess == .granted)") {
            busy = context == .gallery ? [3: [.blue], 8: [.orange, .purple], 14: [.red], 21: [.green], 27: [.pink]] : service.busyDays(inMonthOf: month)
        }
        .help(accessMessage(service.eventAccess) ?? "")
        .accentColor(accent)
    }

    private func dayCell(_ day: Int, isToday: Bool, compact: Bool, big: Bool, tone: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(day)")
                .font(.system(size: compact ? 9.5 : (big ? 15 : 11.5), weight: isToday ? .bold : .medium))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: compact ? 16 : (big ? 30 : 22), height: compact ? 14 : (big ? 28 : 20))
                .background(Circle().fill(isToday ? tone : .clear))
            if !compact {
                HStack(spacing: 1.5) {
                    ForEach(Array((busy[day] ?? []).enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: big ? 5 : 3.5, height: big ? 5 : 3.5)
                    }
                }
                .frame(height: big ? 5 : 3.5)
            }
        }
    }
}

// MARK: - Up next

struct UpNextWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = EventService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var events: [EventService.Event] {
        let source = context == .gallery ? sampleEvents : service.events
        let now = Date()
        let timed = source.filter { !$0.isAllDay && $0.end > now }
        return timed.isEmpty ? source.filter { $0.end > now } : timed
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let list = events
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Up Next", symbol: "calendar.badge.clock", color: .red)
                if let next = list.first {
                    switch model.size {
                    case .small:
                        eventCard(next, now: timeline.date)
                    case .medium, .wide:
                        // Side by side, so the header never gets pushed out of the widget.
                        HStack(alignment: .top, spacing: 12) {
                            eventCard(next, now: timeline.date).frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(list.dropFirst().prefix(3)) { event in
                                    EventRow(event: event, compact: true, showDay: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    default:
                        eventCard(next, now: timeline.date)
                        Divider().opacity(0.4)
                        ForEach(list.dropFirst().prefix(model.size == .tall ? 3 : (model.size == .portrait ? 10 : 6))) { event in
                            EventRow(event: event, compact: true, showDay: true)
                        }
                    }
                } else {
                    Spacer(minLength: 0)
                    Text(accessMessage(service.eventAccess) ?? "Nothing coming up this week. Enjoy it!")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .widgetPadding()
        }
        .usesEvents()
    }

    @ViewBuilder
    private func eventCard(_ event: EventService.Event, now: Date) -> some View {
        let live = event.start <= now && event.end > now
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(event.isAllDay ? "All day" : "\(DateFormats.shortTime(event.start)) – \(DateFormats.shortTime(event.end))")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(Self.countdown(event, now: now))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(style.tone(live ? .green : .red))
                if let join = event.joinURL {
                    Button { NSWorkspace.shared.open(join) } label: {
                        Label("Join", systemImage: "video.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.green))
                    }
                    .buttonStyle(WidgetButtonStyle())
                } else if let location = event.location, !location.isEmpty, model.family != .small {
                    Label(location, systemImage: "mappin").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    static func countdown(_ event: EventService.Event, now: Date) -> String {
        if event.start <= now {
            let left = Int(event.end.timeIntervalSince(now) / 60)
            return "Now · ends in \(Fmt.duration(minutes: max(1, left)))"
        }
        let minutes = Int(ceil(event.start.timeIntervalSince(now) / 60))
        if minutes < 60 * 12 { return "In \(Fmt.duration(minutes: max(1, minutes)))" }
        return DateFormats.string(event.start, template: "EEEE")
    }
}

// MARK: - Week agenda

struct AgendaWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = EventService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private enum Row: Identifiable {
        case day(Date)
        case event(EventService.Event)
        var id: String {
            switch self {
            case .day(let date): return "d\(date.timeIntervalSince1970)"
            case .event(let event): return event.id
            }
        }
    }

    /// Day headings and events in order, cut off when the widget is full.
    private func rows(limit: Int) -> [Row] {
        let source = context == .gallery ? sampleEvents : service.events.filter { $0.end > Date() }
        let calendar = Calendar.current
        let groups = Dictionary(grouping: source) { calendar.startOfDay(for: max($0.start, Date())) }.sorted { $0.key < $1.key }
        var out: [Row] = []
        for (day, events) in groups {
            guard out.count + 1 < limit else { break }
            out.append(.day(day))
            for event in events where out.count < limit { out.append(.event(event)) }
        }
        return out
    }

    var body: some View {
        let calendar = Calendar.current
        let limit = model.family == .large || model.size == .portrait ? 13 : model.size == .tall ? 10 : 5
        let list = rows(limit: limit)
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(title: "This Week", symbol: "list.bullet.rectangle.portrait.fill", color: .red)
            if list.isEmpty {
                Text(accessMessage(service.eventAccess) ?? "Your week is wide open.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(list) { row in
                switch row {
                case .day(let day):
                    Text(calendar.isDateInToday(day) ? "TODAY" : calendar.isDateInTomorrow(day) ? "TOMORROW" : DateFormats.string(day, template: "EEEEMMMd").uppercased())
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(style.tone(.red))
                        .padding(.top, 2)
                case .event(let event):
                    EventRow(event: event, compact: true)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
        .usesEvents()
    }
}

// MARK: - Class schedule

enum ScheduleKeys {
    static let periods = ConfigKey("periods", "8:00-8:50 Math\n8:55-9:45 English\n9:50-10:40 Science\n10:45-11:35 History\n11:40-12:20 Lunch\n12:25-1:15 Spanish\n1:20-2:10 PE\n2:15-3:05 Art")
    static let weekdaysOnly = ConfigKey("weekdaysOnly", true)
}

struct ClassPeriod: Identifiable, Equatable {
    var id: Int { start }
    let name: String
    let start: Int // minutes after midnight
    let end: Int

    /// "8:00-8:50 Math" or "Math 8:00-8:50" — afternoon times like 1:20 are read as PM.
    static func parse(_ text: String) -> [ClassPeriod] {
        let pattern = #"(\d{1,2}):(\d{2})\s*(am|pm)?\s*[-–to]+\s*(\d{1,2}):(\d{2})\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        var out: [ClassPeriod] = []
        var last = 0
        for raw in text.split(separator: "\n") {
            let line = String(raw)
            guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { continue }
            func group(_ i: Int) -> String? {
                guard let r = Range(match.range(at: i), in: line) else { return nil }
                return String(line[r])
            }
            func minutes(_ h: Int, _ m: Int, _ mer: String?) -> Int {
                var hour = h
                if let mer = mer?.lowercased() {
                    if mer == "pm" && hour < 12 { hour += 12 }
                    if mer == "am" && hour == 12 { hour = 0 }
                } else if hour < 7 {
                    hour += 12 // school day: 1:20 means 1:20 PM
                }
                return hour * 60 + m
            }
            var start = minutes(Int(group(1) ?? "0") ?? 0, Int(group(2) ?? "0") ?? 0, group(3))
            var end = minutes(Int(group(4) ?? "0") ?? 0, Int(group(5) ?? "0") ?? 0, group(6))
            if start < last && start + 720 < 1440 { start += 720 }
            if end <= start { end += 720 }
            last = end
            let name = (line.replacingCharacters(in: Range(match.range, in: line)!, with: "")).trimmingCharacters(in: CharacterSet(charactersIn: " |-–:,\t"))
            out.append(ClassPeriod(name: name.isEmpty ? "Class" : name, start: start, end: end))
        }
        return out.sorted { $0.start < $1.start }
    }

    static func clock(_ minutes: Int) -> String {
        let date = Calendar.current.date(bySettingHour: minutes / 60 % 24, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        return DateFormats.shortTime(date)
    }
}

struct ClassScheduleWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let periods = ClassPeriod.parse(model[ScheduleKeys.periods])
            let now = timeline.date
            let calendar = Calendar.current
            let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
            let weekend = calendar.isDateInWeekend(now) && model[ScheduleKeys.weekdaysOnly]
            let current = weekend ? nil : periods.first { $0.start <= minute && minute < $0.end }
            let next = weekend ? nil : periods.first { $0.start > minute }
            let tone = style.tone(.indigo)
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "Schedule", symbol: "graduationcap.fill", color: .indigo)
                if periods.isEmpty {
                    Text("Add your classes in Edit Widget, one per line: 8:00-8:50 Math").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if weekend {
                    Text("No school today 🎉").font(.system(size: 15, weight: .semibold))
                } else if let current {
                    Text("NOW").font(.system(size: 9.5, weight: .bold)).foregroundStyle(tone)
                    Text(current.name).font(.system(size: 17, weight: .bold)).fitLine()
                    ProgressView(value: Double(minute - current.start), total: Double(max(1, current.end - current.start)))
                        .tint(tone)
                    Text("\(current.end - minute) min left · ends \(ClassPeriod.clock(current.end))").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if let next {
                    Text("NEXT").font(.system(size: 9.5, weight: .bold)).foregroundStyle(tone)
                    Text(next.name).font(.system(size: 17, weight: .bold)).fitLine()
                    Text("Starts \(ClassPeriod.clock(next.start)) · in \(Fmt.duration(minutes: next.start - minute))").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Done for today ✅").font(.system(size: 15, weight: .semibold))
                }
                // After the last class (and on weekends) the list shows the next school day instead of nothing.
                let finished = !periods.isEmpty && (weekend || (current == nil && next == nil))
                let upcoming = finished ? periods : periods.filter { $0.end > minute }
                let big = model.family == .large
                if (model.family != .small || model.size == .tall) && !upcoming.isEmpty {
                    if finished {
                        Text(nextSchoolDay(after: now).uppercased())
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(tone)
                            .padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: big ? 0 : 2) {
                        ForEach(upcoming.prefix(big ? 10 : (model.size == .tall ? 6 : 3))) { period in
                            HStack {
                                Text(ClassPeriod.clock(period.start))
                                    .font(.system(size: big ? 12 : 10.5, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: big ? 66 : 58, alignment: .leading)
                                Text(period.name)
                                    .font(.system(size: big ? 13.5 : 11.5, weight: period == current ? .bold : .regular))
                                    .lineLimit(1)
                            }
                            .frame(maxHeight: big ? 30 : nil)
                        }
                    }
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .widgetPadding()
        }
    }

    /// "Tomorrow", or the weekday name when school skips the weekend.
    private func nextSchoolDay(after now: Date) -> String {
        let calendar = Calendar.current
        var day = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        if model[ScheduleKeys.weekdaysOnly] {
            while calendar.isDateInWeekend(day) { day = calendar.date(byAdding: .day, value: 1, to: day) ?? day }
        }
        return calendar.isDateInTomorrow(day) ? "Tomorrow" : DateFormats.string(day, template: "EEEE")
    }
}

// MARK: - Homework

enum HomeworkKeys {
    /// One item per entry: "title|yyyy-MM-dd|done" (done = 1).
    static let items = ConfigKey<[String]>("items", [])
}

struct HomeworkItem: Identifiable, Equatable {
    var id: String { raw }
    let raw: String
    let title: String
    let due: Date?
    let done: Bool

    init(raw: String) {
        self.raw = raw
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        title = parts.first ?? raw
        due = parts.count > 1 ? DateFormats.formatter(format: "yyyy-MM-dd").date(from: parts[1]) : nil
        done = parts.count > 2 && parts[2] == "1"
    }

    static func encode(title: String, due: Date?, done: Bool) -> String {
        "\(title.replacingOccurrences(of: "|", with: "/"))|\(due.map { DateFormats.string($0, format: "yyyy-MM-dd") } ?? "")|\(done ? "1" : "0")"
    }

    /// "Essay fri", "Lab report tomorrow", "Read ch 4 10/21" → title + due date.
    static func parse(_ text: String, today: Date = Date()) -> (String, Date?) {
        let calendar = Calendar.current
        var words = text.split(separator: " ").map(String.init)
        guard let last = words.last?.lowercased() else { return (text, nil) }
        var due: Date?
        let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if last == "today" { due = today }
        else if last == "tomorrow" || last == "tmrw" { due = calendar.date(byAdding: .day, value: 1, to: today) }
        else if let index = weekdays.firstIndex(where: { last.hasPrefix($0) }) {
            var components = DateComponents()
            components.weekday = index + 1
            due = calendar.nextDate(after: today, matching: components, matchingPolicy: .nextTime)
        } else if last.contains("/"), let month = Int(last.split(separator: "/")[0]), let day = Int(last.split(separator: "/").dropFirst().first ?? "") {
            var components = calendar.dateComponents([.year], from: today)
            components.month = month
            components.day = day
            due = calendar.date(from: components)
        }
        if due != nil { words.removeLast() }
        if words.last?.lowercased() == "due" { words.removeLast() }
        return (words.joined(separator: " "), due.map { calendar.startOfDay(for: $0) })
    }
}

struct HomeworkWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style
    @State private var draft = ""

    private var items: [HomeworkItem] {
        let raw = model[HomeworkKeys.items]
        let source = raw.isEmpty && context == .gallery
            ? [HomeworkItem.encode(title: "Math worksheet", due: Date(), done: false),
               HomeworkItem.encode(title: "English essay", due: Date().addingTimeInterval(86400 * 2), done: false),
               HomeworkItem.encode(title: "Science lab", due: Date().addingTimeInterval(-86400), done: false)]
            : raw
        return source.map(HomeworkItem.init).filter { !$0.done }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    var body: some View {
        let list = items
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Homework", symbol: "backpack.fill", color: .orange, trailing: list.isEmpty ? nil : "\(list.count) left")
            if list.isEmpty {
                Text("All caught up! 🎉").font(.system(size: 13, weight: .semibold))
            }
            ForEach(list.prefix(model.family == .small ? 3 : model.family == .medium ? 3 : 9)) { item in
                HStack(spacing: 7) {
                    Button { complete(item) } label: {
                        Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .buttonStyle(WidgetButtonStyle())
                    Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    if let due = item.due { dueLabel(due) }
                }
            }
            Spacer(minLength: 0)
            if model.family != .small {
                TextField("Add: Essay fri", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
                    .onSubmit(add)
                    .disabled(context != .desktop)
            }
        }
        .widgetPadding()
    }

    private func dueLabel(_ due: Date) -> some View {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: due).day ?? 0
        let (text, color): (String, Color) = days < 0 ? ("Late", .red) : days == 0 ? ("Today", .orange) : days == 1 ? ("Tmrw", .yellow) : (DateFormats.string(due, template: days < 7 ? "EEE" : "MMMd"), .secondary)
        return Text(text).font(.system(size: 10, weight: .bold)).foregroundStyle(color == .secondary ? Color.secondary : style.tone(color))
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let (title, due) = HomeworkItem.parse(text)
        model.config[HomeworkKeys.items] = model[HomeworkKeys.items] + [HomeworkItem.encode(title: title, due: due, done: false)]
        draft = ""
    }

    private func complete(_ item: HomeworkItem) {
        guard context == .desktop else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            model.config[HomeworkKeys.items] = model[HomeworkKeys.items].filter { $0 != item.raw }
        }
        NSSound(named: "Pop")?.play()
    }
}

// MARK: - Bible reading plan

enum ReadingPlan: String, ConfigOption {
    case wholeBible, newTestament, gospels, psalmsProverbs

    var label: String {
        switch self {
        case .wholeBible: return "Whole Bible in a year"
        case .newTestament: return "New Testament in 90 days"
        case .gospels: return "The Gospels in 30 days"
        case .psalmsProverbs: return "Psalms & Proverbs in 60 days"
        }
    }

    var days: Int {
        switch self {
        case .wholeBible: return 365
        case .newTestament: return 90
        case .gospels: return 30
        case .psalmsProverbs: return 60
        }
    }

    var books: ArraySlice<(String, Int)> {
        switch self {
        case .wholeBible: return BibleBooks.all[...]
        case .newTestament: return BibleBooks.all[39...]
        case .gospels: return BibleBooks.all[39..<43]
        case .psalmsProverbs: return BibleBooks.all[18..<20]
        }
    }
}

enum BibleBooks {
    static let all: [(String, Int)] = [
        ("Genesis", 50), ("Exodus", 40), ("Leviticus", 27), ("Numbers", 36), ("Deuteronomy", 34), ("Joshua", 24), ("Judges", 21), ("Ruth", 4),
        ("1 Samuel", 31), ("2 Samuel", 24), ("1 Kings", 22), ("2 Kings", 25), ("1 Chronicles", 29), ("2 Chronicles", 36), ("Ezra", 10),
        ("Nehemiah", 13), ("Esther", 10), ("Job", 42), ("Psalms", 150), ("Proverbs", 31), ("Ecclesiastes", 12), ("Song of Solomon", 8),
        ("Isaiah", 66), ("Jeremiah", 52), ("Lamentations", 5), ("Ezekiel", 48), ("Daniel", 12), ("Hosea", 14), ("Joel", 3), ("Amos", 9),
        ("Obadiah", 1), ("Jonah", 4), ("Micah", 7), ("Nahum", 3), ("Habakkuk", 3), ("Zephaniah", 3), ("Haggai", 2), ("Zechariah", 14),
        ("Malachi", 4), ("Matthew", 28), ("Mark", 16), ("Luke", 24), ("John", 21), ("Acts", 28), ("Romans", 16), ("1 Corinthians", 16),
        ("2 Corinthians", 13), ("Galatians", 6), ("Ephesians", 6), ("Philippians", 4), ("Colossians", 4), ("1 Thessalonians", 5),
        ("2 Thessalonians", 3), ("1 Timothy", 6), ("2 Timothy", 4), ("Titus", 3), ("Philemon", 1), ("Hebrews", 13), ("James", 5),
        ("1 Peter", 5), ("2 Peter", 3), ("1 John", 5), ("2 John", 1), ("3 John", 1), ("Jude", 1), ("Revelation", 22),
    ]
}

enum ReadingKeys {
    static let plan = ConfigKey("plan", ReadingPlan.wholeBible)
    static let start = ConfigKey("start", Date.distantPast)
    static let done = ConfigKey<[String]>("done", []) // yyyy-MM-dd days read
}

struct ReadingPlanWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var start: Date {
        let saved = model[ReadingKeys.start]
        if saved != .distantPast { return saved }
        let calendar = Calendar.current
        return model[ReadingKeys.plan] == .wholeBible
            ? calendar.date(from: calendar.dateComponents([.year], from: Date())) ?? Date()
            : calendar.startOfDay(for: Date())
    }

    /// Splits the plan's chapters evenly over its days and returns today's passage(s).
    static func reading(plan: ReadingPlan, day: Int) -> (label: String, query: String) {
        let chapters = plan.books.flatMap { book in (1...book.1).map { (book.0, $0) } }
        let index = min(max(0, day), plan.days - 1)
        let from = index * chapters.count / plan.days
        let to = max(from, (index + 1) * chapters.count / plan.days - 1)
        let slice = chapters[from...min(to, chapters.count - 1)]
        var parts: [String] = []
        var current: (String, Int, Int)?
        for (book, chapter) in slice {
            if let c = current, c.0 == book, c.2 + 1 == chapter { current = (book, c.1, chapter) }
            else {
                if let c = current { parts.append(c.1 == c.2 ? "\(c.0) \(c.1)" : "\(c.0) \(c.1)–\(c.2)") }
                current = (book, chapter, chapter)
            }
        }
        if let c = current { parts.append(c.1 == c.2 ? "\(c.0) \(c.1)" : "\(c.0) \(c.1)–\(c.2)") }
        let label = parts.joined(separator: ", ")
        return (label, label.replacingOccurrences(of: "–", with: "-"))
    }

    var body: some View {
        let plan = model[ReadingKeys.plan]
        let calendar = Calendar.current
        let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: Date())).day ?? 0
        let reading = Self.reading(plan: plan, day: day)
        let todayKey = DateFormats.string(Date(), format: "yyyy-MM-dd")
        let done = model[ReadingKeys.done]
        let readToday = done.contains(todayKey)
        let tone = style.tone(.brown)
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Reading Plan", symbol: "book.fill", color: .brown, trailing: "Day \(min(plan.days, day + 1))/\(plan.days)")
            if day >= plan.days {
                Text("Plan complete! 🙌").font(.system(size: 15, weight: .bold))
                Button("Start again") { model.config[ReadingKeys.start] = calendar.startOfDay(for: Date()); model.config[ReadingKeys.done] = [] }
                    .font(.system(size: 11, weight: .semibold)).buttonStyle(WidgetButtonStyle())
            } else {
                Text(reading.label)
                    .font(.system(size: model.family == .small ? 15 : 18, weight: .semibold, design: .serif))
                    .lineLimit(3)
                    .minimumScaleFactor(0.6)
                    .onTapGesture { open(reading.query) }
                    .help("Open in Bible Gateway (KJV)")
                ProgressView(value: Double(min(plan.days, day + 1)), total: Double(plan.days)).tint(tone)
                Spacer(minLength: 0)
                HStack {
                    Button {
                        guard context == .desktop else { return }
                        model.config[ReadingKeys.done] = readToday ? done.filter { $0 != todayKey } : done + [todayKey]
                    } label: {
                        Label(readToday ? "Read" : "Mark read", systemImage: readToday ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(readToday ? Color.green : tone)
                    }
                    .buttonStyle(WidgetButtonStyle())
                    Spacer()
                    Text("🔥 \(Self.streak(done))").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .widgetPadding()
        .onAppear {
            if context == .desktop && model[ReadingKeys.start] == .distantPast { model.config[ReadingKeys.start] = start }
        }
    }

    private func open(_ query: String) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        if let url = URL(string: "https://www.biblegateway.com/passage/?search=\(q)&version=KJV") { NSWorkspace.shared.open(url) }
    }

    static func streak(_ days: [String]) -> Int {
        let set = Set(days)
        var count = 0
        var date = Date()
        if !set.contains(DateFormats.string(date, format: "yyyy-MM-dd")) { date = date.addingTimeInterval(-86400) }
        while set.contains(DateFormats.string(date, format: "yyyy-MM-dd")) {
            count += 1
            date = date.addingTimeInterval(-86400)
        }
        return count
    }
}

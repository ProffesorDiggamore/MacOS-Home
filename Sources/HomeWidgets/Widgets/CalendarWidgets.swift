import SwiftUI

// MARK: - Calendar

enum CalendarKeys {
    static let showEvents = ConfigKey("showEvents", true)
}

struct CalendarWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = EventService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var showEvents: Bool { model[CalendarKeys.showEvents] }
    private var usesSamples: Bool { context == .gallery }

    var body: some View {
        Ticking(everySecond: false) { now in
            content(now)
        }
        .onAppear { if showEvents && !usesSamples { service.retainEvents() } }
        .onDisappear { if showEvents && !usesSamples { service.releaseEvents() } }
        .onChange(of: showEvents) { _, newValue in
            guard !usesSamples else { return }
            if newValue { service.retainEvents() } else { service.releaseEvents() }
        }
    }

    private func upcoming(_ now: Date) -> [EventService.Event] {
        let source = usesSamples ? EventService.sampleEvents : service.events
        return source.filter { $0.end > now }
    }

    private var red: Color { style.tone(.red) }

    @ViewBuilder
    private func content(_ now: Date) -> some View {
        switch model.family {
        case .small:
            VStack(alignment: .leading, spacing: 0) {
                Text(DateFormats.string(now, template: "EEEE").uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(red)
                Text(DateFormats.string(now, template: "d"))
                    .font(.system(size: 50, weight: .light))
                    .monospacedDigit()
                    .padding(.top, -4)
                Spacer(minLength: 0)
                if showEvents, let next = upcoming(now).first {
                    EventRow(event: next, compact: true)
                } else {
                    Text(showEvents ? eventsPlaceholder : DateFormats.string(now, template: "MMMMyyyy"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetPadding(16)

        case .medium:
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(DateFormats.string(now, template: "d"))
                            .font(.system(size: 30, weight: .light))
                        Text(DateFormats.string(now, template: "EEEE").uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(red)
                    }
                    if showEvents {
                        let events = Array(upcoming(now).prefix(3))
                        if events.isEmpty {
                            Text(eventsPlaceholder)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(events) { EventRow(event: $0, compact: false) }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                MonthGrid(date: now, highlight: red, compact: true)
                    .frame(width: 140)
            }
            .widgetPadding()

        case .large:
            VStack(alignment: .leading, spacing: 10) {
                MonthGrid(date: now, highlight: red, compact: false)
                if showEvents {
                    Divider().opacity(0.5)
                    let events = Array(upcoming(now).prefix(5))
                    if events.isEmpty {
                        Text(eventsPlaceholder)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { EventRow(event: $0, compact: false, showDay: true) }
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetPadding(16)
        }
    }

    private var eventsPlaceholder: String {
        if usesSamples { return "No more events today" }
        switch service.eventAccess {
        case .denied: return "Allow Calendar access in System Settings › Privacy"
        case .unavailable: return "Install the app to show events"
        default: return "No more events today"
        }
    }
}

struct EventRow: View {
    let event: EventService.Event
    var compact: Bool
    var showDay = false

    private var timeText: String {
        if event.isAllDay { return showDay ? DateFormats.string(event.start, template: "EEE") + " · All day" : "All day" }
        let time = DateFormats.shortTime(event.start)
        if showDay && !Calendar.current.isDateInToday(event.start) {
            return DateFormats.string(event.start, template: "EEE") + " · " + time
        }
        return time
    }

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(event.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: compact ? 11.5 : 12, weight: .semibold))
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: compact ? 10.5 : 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MonthGrid: View {
    let date: Date
    let highlight: Color
    let compact: Bool

    var body: some View {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let dayCount = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
        let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let today = calendar.component(.day, from: date)
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let orderedSymbols = Array(symbols[(calendar.firstWeekday - 1)...] + symbols[..<(calendar.firstWeekday - 1)])
        let cells: [Int?] = Array(repeating: nil, count: leading) + (1...dayCount).map { Optional($0) }
        let weeks = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(cells[start..<min(start + 7, cells.count)]) + [Int?](repeating: nil, count: max(0, start + 7 - cells.count))
        }
        let fontSize: CGFloat = compact ? 9.5 : 13

        return VStack(spacing: compact ? 2 : 6) {
            Text(DateFormats.string(date, template: compact ? "MMMM" : "MMMMyyyy").uppercased())
                .font(.system(size: compact ? 10 : 13, weight: .bold))
                .foregroundStyle(highlight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, compact ? 2 : 4)
            HStack(spacing: 0) {
                ForEach(Array(orderedSymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: fontSize - 1, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        ZStack {
                            if let day {
                                if day == today {
                                    Circle().fill(highlight)
                                        .frame(width: fontSize * 1.9, height: fontSize * 1.9)
                                }
                                Text("\(day)")
                                    .font(.system(size: fontSize, weight: day == today ? .bold : .medium))
                                    .foregroundStyle(day == today ? Color.white : Color.primary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: fontSize * 1.75)
                    }
                }
            }
        }
    }
}

// MARK: - Countdown

enum CountdownKeys {
    static let title = ConfigKey("title", "New Year")
    static var target: ConfigKey<Date> { ConfigKey("target", Countdown.nextNewYear()) }
    static let symbol = ConfigKey("symbol", CountdownSymbol.party)
}

enum CountdownSymbol: String, ConfigOption {
    case party, gift, cake, star, airplane, graduation, heart, sun, cross, calendar

    var label: String {
        switch self {
        case .party: return "Celebration"
        case .gift: return "Gift"
        case .cake: return "Birthday"
        case .star: return "Star"
        case .airplane: return "Trip"
        case .graduation: return "Graduation"
        case .heart: return "Heart"
        case .sun: return "Summer"
        case .cross: return "Church"
        case .calendar: return "Calendar"
        }
    }

    var symbol: String {
        switch self {
        case .party: return "party.popper.fill"
        case .gift: return "gift.fill"
        case .cake: return "birthday.cake.fill"
        case .star: return "star.fill"
        case .airplane: return "airplane"
        case .graduation: return "graduationcap.fill"
        case .heart: return "heart.fill"
        case .sun: return "sun.max.fill"
        case .cross: return "cross.fill"
        case .calendar: return "calendar"
        }
    }
}

enum Countdown {
    static func nextNewYear(from date: Date = Date()) -> Date {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? date.addingTimeInterval(86400 * 30)
    }
}

struct CountdownWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetStyle) private var style

    static func label(days: Int, remaining: TimeInterval) -> (number: String, unit: String) {
        if days == 0 && remaining > 0 {
            let hours = Int(remaining / 3600)
            if hours > 0 { return ("\(hours)", hours == 1 ? "hour until" : "hours until") }
            return ("\(Int(remaining / 60))", "minutes until")
        }
        if days == 0 { return ("🎉", "today is") }
        if days < 0 { return ("\(-days)", -days == 1 ? "day since" : "days since") }
        return ("\(days)", days == 1 ? "day until" : "days until")
    }

    var body: some View {
        Ticking(everySecond: false) { now in
            content(now)
        }
    }

    @ViewBuilder
    private func content(_ now: Date) -> some View {
        let target = model[CountdownKeys.target]
        let title = model[CountdownKeys.title]
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: target)).day ?? 0
        let label = Self.label(days: days, remaining: target.timeIntervalSince(now))
        let number = label.number
        let unit = label.unit
        let icon = model[CountdownKeys.symbol].symbol

        switch model.family {
        case .small, .large:
            VStack(alignment: .leading, spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(style.tone(accent))
                Spacer(minLength: 0)
                Text(number)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .fitLine(0.4)
                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .fitLine(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetPadding(16)
        case .medium:
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(style.tone(accent))
                    Spacer(minLength: 0)
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .fitLine(0.6)
                    Text(DateFormats.string(target, template: "EEEEMMMMdyyyy"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fitLine()
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(number)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .fitLine(0.4)
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .widgetPadding(18)
        }
    }
}

// MARK: - Year progress

enum YearProgressKeys {
    static let showDots = ConfigKey("showDots", true)
}

struct YearProgressWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetStyle) private var style

    var body: some View {
        Ticking(everySecond: false) { now in
            content(now)
        }
    }

    private func fraction(_ component: Calendar.Component, _ now: Date) -> Double {
        guard let interval = Calendar.current.dateInterval(of: component, for: now) else { return 0 }
        return now.timeIntervalSince(interval.start) / interval.duration
    }

    @ViewBuilder
    private func content(_ now: Date) -> some View {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: now) ?? 1
        let daysInYear = calendar.range(of: .day, in: .year, for: now)?.count ?? 365
        let yearFraction = fraction(.year, now)
        let tone = style.tone(accent)

        switch model.family {
        case .small where model.size == .tall:
            // The dots fill the middle of the tall shape.
            VStack(alignment: .leading, spacing: 8) {
                Text(String(year))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tone)
                DayDots(total: daysInYear, filled: dayOfYear, color: tone)
                    .frame(maxHeight: .infinity)
                Text(String(format: "%.1f%%", yearFraction * 100))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .fitLine(0.5)
                Text("Day \(dayOfYear) of \(daysInYear)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetPadding(16)
        case .small:
            VStack(alignment: .leading, spacing: 4) {
                Text(String(year))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tone)
                Spacer(minLength: 0)
                Text(String(format: "%.1f%%", yearFraction * 100))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .fitLine(0.5)
                BarMeter(value: yearFraction, color: accent, height: 8)
                Text("Day \(dayOfYear) of \(daysInYear)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetPadding(16)
        case .medium:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(String(year)) is \(Int(yearFraction * 100))% complete")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(daysInYear - dayOfYear) days left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                DayDots(total: daysInYear, filled: dayOfYear, color: tone)
            }
            .widgetPadding()
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(year)).font(.system(size: 22, weight: .bold))
                    Spacer()
                    Text(String(format: "%.1f%%", yearFraction * 100))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(tone)
                        .monospacedDigit()
                }
                DayDots(total: daysInYear, filled: dayOfYear, color: tone)
                    .frame(minHeight: 150, maxHeight: .infinity)
                ProgressRow(label: "Month", value: fraction(.month, now), color: tone)
                ProgressRow(label: "Week", value: fraction(.weekOfYear, now), color: tone)
                ProgressRow(label: "Today", value: fraction(.day, now), color: tone)
            }
            .widgetPadding(16)
        }
    }
}

private struct ProgressRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            BarMeter(value: value, color: color, height: 6)
            Text(Fmt.percent(value))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}

/// One dot per day of the year.
struct DayDots: View {
    let total: Int
    let filled: Int
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard total > 0, size.width > 1, size.height > 1 else { return }
            let columns = max(1, Int((Double(total) * Double(size.width / size.height)).squareRoot().rounded(.up)))
            let rows = max(1, Int((Double(total) / Double(columns)).rounded(.up)))
            let cellWidth = size.width / CGFloat(max(columns, 1))
            let cellHeight = size.height / CGFloat(max(rows, 1))
            let diameter = max(2, min(cellWidth, cellHeight) * 0.62)
            for index in 0..<total {
                let column = index % columns
                let row = index / columns
                let rect = CGRect(x: CGFloat(column) * cellWidth + (cellWidth - diameter) / 2,
                                  y: CGFloat(row) * cellHeight + (cellHeight - diameter) / 2,
                                  width: diameter, height: diameter)
                let shading: GraphicsContext.Shading
                if index < filled - 1 {
                    shading = .color(color)
                } else if index == filled - 1 {
                    shading = .color(.primary)
                } else {
                    shading = .color(color.opacity(0.2))
                }
                context.fill(Path(ellipseIn: rect), with: shading)
            }
        }
    }
}

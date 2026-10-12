import SwiftUI

enum ClockKeys {
    static let showSeconds = ConfigKey("showSeconds", false)
    static let use24Hour = ConfigKey("use24Hour", false)
    static let showDate = ConfigKey("showDate", true)
    static let design = ConfigKey("design", ClockFont.rounded)
    static let timeZone = ConfigKey("timeZone", "")
}

enum ClockFont: String, ConfigOption {
    case standard, rounded, serif, mono, thin

    var label: String {
        switch self {
        case .standard: return "SF Pro"
        case .rounded: return "Rounded"
        case .serif: return "New York"
        case .mono: return "Monospaced"
        case .thin: return "Thin"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .standard: return .system(size: size, weight: .semibold, design: .default)
        case .rounded: return .system(size: size, weight: .semibold, design: .rounded)
        case .serif: return .system(size: size, weight: .medium, design: .serif)
        case .mono: return .system(size: size, weight: .medium, design: .monospaced)
        case .thin: return .system(size: size, weight: .thin, design: .default)
        }
    }
}

extension TimeZone {
    /// Empty string means the Mac's current time zone.
    static func named(_ identifier: String) -> TimeZone {
        identifier.isEmpty ? .current : (TimeZone(identifier: identifier) ?? .current)
    }

    /// "America/Los_Angeles" → "Los Angeles"
    var cityName: String {
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        return last.replacingOccurrences(of: "_", with: " ")
    }
}

// MARK: - Digital clock

struct ClockWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let seconds = model[ClockKeys.showSeconds]
        Ticking(everySecond: seconds) { date in
            content(date)
        }
    }

    @ViewBuilder
    private func content(_ date: Date) -> some View {
        let zone = TimeZone.named(model[ClockKeys.timeZone])
        let use24 = model[ClockKeys.use24Hour]
        let seconds = model[ClockKeys.showSeconds]
        let fontChoice = model[ClockKeys.design]
        let time = DateFormats.time(date, use24Hour: use24, seconds: seconds, timeZone: zone)
        let meridiem = use24 ? nil : DateFormats.meridiem(date, timeZone: zone)
        let showDate = model[ClockKeys.showDate]
        let place = model[ClockKeys.timeZone].isEmpty ? nil : zone.cityName

        switch model.family {
        case .small:
            VStack(alignment: .leading, spacing: 2) {
                Text(DateFormats.string(date, template: "EEEE", timeZone: zone).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(style.tone(accent))
                    .fitLine()
                if let place {
                    Text(place)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fitLine()
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(time)
                        .font(fontChoice.font(size: seconds ? 34 : 46))
                        .monospacedDigit()
                        .fitLine(0.5)
                    if let meridiem {
                        Text(meridiem)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                if showDate {
                    Text(DateFormats.string(date, template: "MMMMd", timeZone: zone))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fitLine()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetPadding(16)

        case .medium:
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(time)
                        .font(fontChoice.font(size: seconds ? 52 : 66))
                        .monospacedDigit()
                        .fitLine(0.5)
                    if let meridiem {
                        Text(meridiem)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showDate || place != nil {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(DateFormats.string(date, template: "EEEE", timeZone: zone).uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(style.tone(accent))
                        Text(DateFormats.string(date, template: "d", timeZone: zone))
                            .font(.system(size: 36, weight: .light))
                            .monospacedDigit()
                        Text(place ?? DateFormats.string(date, template: "MMMM", timeZone: zone))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .fitLine()
                }
            }
            .widgetPadding(20)

        case .large:
            VStack(spacing: 6) {
                Text(DateFormats.string(date, template: "EEEE", timeZone: zone).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(style.tone(accent))
                Spacer(minLength: 0)
                Text(time)
                    .font(fontChoice.font(size: seconds ? 76 : 96))
                    .monospacedDigit()
                    .fitLine(0.4)
                if let meridiem {
                    Text(meridiem)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if showDate {
                    Text(DateFormats.string(date, template: "MMMMdyyyy", timeZone: zone))
                        .font(.system(size: 17, weight: .medium))
                    let calendar = Calendar.current
                    let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
                    let week = calendar.component(.weekOfYear, from: date)
                    Text("Week \(week) · Day \(day)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if let place {
                    Text(place).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .widgetPadding(22)
        }
    }
}

// MARK: - Analog clock

enum AnalogKeys {
    static let showSeconds = ConfigKey("showSeconds", true)
    static let numerals = ConfigKey("numerals", ClockNumerals.all)
    static let face = ConfigKey("face", ClockFace.auto)
    static let timeZone = ConfigKey("timeZone", "")
}

enum ClockNumerals: String, ConfigOption {
    case all, quarters, hidden
    var label: String {
        switch self {
        case .all: return "1–12"
        case .quarters: return "12, 3, 6, 9"
        case .hidden: return "None"
        }
    }
}

enum ClockFace: String, ConfigOption {
    case auto, light, dark
    var label: String {
        switch self {
        case .auto: return "Match Appearance"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

struct AnalogClockFace: View {
    let date: Date
    let timeZone: TimeZone
    var showSeconds = true
    var numerals: ClockNumerals = .all
    var dark: Bool
    var secondColor: Color = .orange

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(parts.hour ?? 0)
        let minute = Double(parts.minute ?? 0)
        let second = Double(parts.second ?? 0)
        let ink = dark ? Color.white : Color.black
        let face = dark ? Color(white: 0.1) : Color.white
        let numeralStyle = numerals
        let seconds = showSeconds
        let accent = secondColor

        return Canvas { context, size in
            let side = min(size.width, size.height)
            let radius = side / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ angle: Double, _ distance: CGFloat) -> CGPoint {
                CGPoint(x: center.x + distance * CGFloat(sin(angle)), y: center.y - distance * CGFloat(cos(angle)))
            }

            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: side, height: side)), with: .color(face))

            for tick in 0..<60 {
                let angle = Double(tick) / 60 * 2 * .pi
                let isHour = tick % 5 == 0
                var path = Path()
                path.move(to: point(angle, radius * 0.94))
                path.addLine(to: point(angle, radius * (isHour ? 0.85 : 0.9)))
                context.stroke(path, with: .color(ink.opacity(isHour ? 0.85 : 0.3)),
                               style: StrokeStyle(lineWidth: isHour ? max(1.2, radius * 0.025) : max(0.6, radius * 0.011), lineCap: .round))
            }

            if numeralStyle != .hidden {
                for number in 1...12 where numeralStyle == .all || number % 3 == 0 {
                    let angle = Double(number) / 12 * 2 * .pi
                    let text = Text("\(number)")
                        .font(.system(size: radius * 0.19, weight: .medium, design: .rounded))
                        .foregroundStyle(ink)
                    context.draw(text, at: point(angle, radius * 0.69))
                }
            }

            func hand(_ angle: Double, length: CGFloat, width: CGFloat, color: Color, tail: CGFloat = 0) {
                var path = Path()
                path.move(to: point(angle + .pi, radius * tail))
                path.addLine(to: point(angle, radius * length))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }

            let hourAngle = (hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12 * 2 * .pi
            let minuteAngle = (minute + second / 60) / 60 * 2 * .pi
            hand(hourAngle, length: 0.5, width: max(2.5, radius * 0.07), color: ink)
            hand(minuteAngle, length: 0.78, width: max(2, radius * 0.05), color: ink)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.06, y: center.y - radius * 0.06, width: radius * 0.12, height: radius * 0.12)), with: .color(ink))
            if seconds {
                let secondAngle = second / 60 * 2 * .pi
                hand(secondAngle, length: 0.86, width: max(1, radius * 0.018), color: accent, tail: 0.16)
                context.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.035, y: center.y - radius * 0.035, width: radius * 0.07, height: radius * 0.07)), with: .color(accent))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct AnalogClockWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetStyle) private var style

    var body: some View {
        Ticking(everySecond: model[AnalogKeys.showSeconds]) { date in
            content(date)
        }
    }

    private var dark: Bool {
        switch model[AnalogKeys.face] {
        case .light: return false
        case .dark: return true
        case .auto: return scheme == .dark
        }
    }

    @ViewBuilder
    private func content(_ date: Date) -> some View {
        let zone = TimeZone.named(model[AnalogKeys.timeZone])
        let face = AnalogClockFace(date: date, timeZone: zone, showSeconds: model[AnalogKeys.showSeconds],
                                   numerals: model[AnalogKeys.numerals], dark: dark,
                                   secondColor: style == .tinted ? .white : .orange)
        switch model.family {
        case .small:
            face.padding(10)
        case .medium:
            HStack(spacing: 18) {
                face
                VStack(alignment: .leading, spacing: 4) {
                    Text(model[AnalogKeys.timeZone].isEmpty ? "Local Time" : zone.cityName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(DateFormats.shortTime(date, timeZone: zone))
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .fitLine()
                    Text(DateFormats.string(date, template: "EEEEMMMMd", timeZone: zone))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fitLine()
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        case .large:
            VStack(spacing: 10) {
                face
                Text(DateFormats.string(date, template: "EEEEMMMMd", timeZone: zone))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }
}

// MARK: - World clock

enum WorldClockKeys {
    static let zones = ConfigKey<[String]>("zones", ["America/Los_Angeles", "America/New_York", "Europe/London", "Asia/Tokyo"])
    static let use24Hour = ConfigKey("use24Hour", false)
}

struct WorldClockWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.colorScheme) private var scheme

    private var zones: [TimeZone] {
        let list = model[WorldClockKeys.zones].compactMap(TimeZone.init(identifier:))
        return list.isEmpty ? [.current] : list
    }

    var body: some View {
        Ticking(everySecond: model.family == .medium) { date in
            switch model.family {
            case .small: list(date, limit: 4, compact: true)
            case .medium: faces(date)
            case .large: list(date, limit: 7, compact: false)
            }
        }
    }

    private func time(_ date: Date, _ zone: TimeZone) -> String {
        if model[WorldClockKeys.use24Hour] {
            return DateFormats.string(date, format: "HH:mm", timeZone: zone)
        }
        return DateFormats.shortTime(date, timeZone: zone)
    }

    private func dayAndOffset(_ date: Date, _ zone: TimeZone) -> String {
        let local = Calendar.current
        var remote = Calendar.current
        remote.timeZone = zone
        let here = local.dateComponents([.year, .month, .day], from: date)
        let there = remote.dateComponents([.year, .month, .day], from: date)
        let localDay = local.date(from: here) ?? date
        let remoteDay = local.date(from: there) ?? date
        let difference = local.dateComponents([.day], from: localDay, to: remoteDay).day ?? 0
        let day = difference == 0 ? "Today" : (difference > 0 ? "Tomorrow" : "Yesterday")
        let offset = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        if offset == 0 { return day }
        let hours = offset == offset.rounded() ? String(Int(offset)) : String(format: "%.1f", offset)
        return "\(day), \(offset > 0 ? "+" : "")\(hours)h"
    }

    private func isDaytime(_ date: Date, _ zone: TimeZone) -> Bool {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        return (6..<18).contains(hour)
    }

    private func faces(_ date: Date) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(zones.prefix(4).enumerated()), id: \.offset) { _, zone in
                VStack(spacing: 6) {
                    AnalogClockFace(date: date, timeZone: zone, showSeconds: true, numerals: .hidden,
                                    dark: !isDaytime(date, zone))
                        .frame(width: 66, height: 66)
                    Text(zone.cityName)
                        .font(.system(size: 11, weight: .semibold))
                        .fitLine(0.7)
                    Text(dayAndOffset(date, zone))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .fitLine(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
    }

    private func list(_ date: Date, limit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            WidgetHeader(title: "World Clock", symbol: "globe", color: .orange)
            ForEach(Array(zones.prefix(limit).enumerated()), id: \.offset) { _, zone in
                HStack(spacing: 8) {
                    if !compact {
                        AnalogClockFace(date: date, timeZone: zone, showSeconds: false, numerals: .hidden,
                                        dark: !isDaytime(date, zone))
                            .frame(width: 30, height: 30)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(zone.cityName)
                            .font(.system(size: compact ? 12 : 14, weight: .semibold))
                            .fitLine(0.7)
                        if !compact {
                            Text(dayAndOffset(date, zone))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(time(date, zone))
                        .font(.system(size: compact ? 13 : 20, weight: compact ? .medium : .regular))
                        .monospacedDigit()
                        .foregroundStyle(compact ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                        .fitLine(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }
}

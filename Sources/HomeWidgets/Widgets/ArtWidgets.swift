import SwiftUI

// Big type and time rings.

// MARK: - Big date

enum BigDateKeys {
    static let gradient = ConfigKey("gradient", true)
}

struct BigDateWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetAccent) private var accent

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            let tone = style.tone(accent)
            let fill: AnyShapeStyle = model[BigDateKeys.gradient] && style != .tinted
                ? AnyShapeStyle(LinearGradient(colors: [tone, tone.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(tone)
            if model.family == .small {
                VStack(spacing: -6) {
                    Text(DateFormats.string(date, template: "EEEE").uppercased())
                        .font(.system(size: 12, weight: .heavy)).tracking(2).foregroundStyle(.secondary)
                    Text(DateFormats.string(date, format: "d"))
                        .font(.system(size: 92, weight: .black, design: .rounded))
                        .foregroundStyle(fill)
                        .fitLine(0.5)
                    Text(DateFormats.string(date, template: "MMMM").uppercased())
                        .font(.system(size: 12, weight: .heavy)).tracking(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    Text(DateFormats.string(date, format: "d"))
                        .font(.system(size: 104, weight: .black, design: .rounded))
                        .foregroundStyle(fill)
                        .fitLine(0.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateFormats.string(date, template: "EEEE")).font(.system(size: 24, weight: .bold))
                        Text(DateFormats.string(date, template: "MMMMyyyy")).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                        Text("Week \(Calendar.current.component(.weekOfYear, from: date)) · Day \(Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1)")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding(18)
            }
        }
    }
}

// MARK: - Time rings

struct TimeRingsWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    private static let rings: [(String, Calendar.Component, Color)] = [
        ("Day", .day, Color(hex: 0xFA114F)),
        ("Week", .weekOfYear, Color(hex: 0x92E82A)),
        ("Month", .month, Color(hex: 0x1EEAEF)),
        ("Year", .year, Color(hex: 0xFFD60A)),
    ]

    static func progress(_ component: Calendar.Component, at date: Date) -> Double {
        guard let interval = Calendar.current.dateInterval(of: component, for: date) else { return 0 }
        return date.timeIntervalSince(interval.start) / interval.duration
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let values = Self.rings.map { ($0.0, Self.progress($0.1, at: timeline.date), $0.2) }
            HStack(spacing: 14) {
                ZStack {
                    ForEach(values.indices, id: \.self) { index in
                        let inset = CGFloat(index) * 13
                        Circle().stroke(values[index].2.opacity(0.18), lineWidth: 10).padding(inset)
                        Circle()
                            .trim(from: 0, to: max(0.003, values[index].1))
                            .stroke(style == .tinted ? Color.white : values[index].2, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(inset)
                    }
                }
                .padding(5)
                .aspectRatio(1, contentMode: .fit)
                if model.family != .small {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(values.indices, id: \.self) { index in
                            HStack(spacing: 6) {
                                Circle().fill(values[index].2).frame(width: 7, height: 7)
                                Text(values[index].0).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(Int(values[index].1 * 100))%").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .widgetPadding(12)
        }
    }
}

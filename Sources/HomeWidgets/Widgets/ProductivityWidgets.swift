import SwiftUI
import AppKit
import UserNotifications

// MARK: - Reminders

struct RemindersWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = EventService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var isSample: Bool { context == .gallery }
    private var reminders: [EventService.Reminder] { isSample ? EventService.sampleReminders : service.reminders }

    var body: some View {
        content
            .onAppear { if !isSample { service.retainReminders() } }
            .onDisappear { if !isSample { service.releaseReminders() } }
    }

    @ViewBuilder
    private var content: some View {
        let limit = model.family == .large ? 10 : (model.family == .medium ? 4 : 3)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "list.bullet.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(style.tone(.orange))
                Spacer()
                Text("\(reminders.count)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
            }
            Text("Reminders")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(style.tone(.orange))
                .padding(.top, -6)
            if !isSample && service.reminderAccess == .denied {
                Text("Allow Reminders access in System Settings › Privacy & Security.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if !isSample && service.reminderAccess == .unavailable {
                Text("Install the app to show reminders.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            } else if reminders.isEmpty {
                Text("All done! 🎉")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reminders.prefix(limit)) { reminder in
                    ReminderRow(reminder: reminder, compact: model.family == .small) {
                        if !isSample { service.complete(reminder.id) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }
}

private struct ReminderRow: View {
    let reminder: EventService.Reminder
    let compact: Bool
    let onComplete: () -> Void
    @State private var checked = false

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Button {
                checked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onComplete() }
            } label: {
                Image(systemName: checked ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: compact ? 13 : 15, weight: .regular))
                    .foregroundStyle(checked ? reminder.color : Color.secondary)
            }
            .buttonStyle(WidgetButtonStyle())
            VStack(alignment: .leading, spacing: 0) {
                Text(reminder.title)
                    .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(checked)
                if !compact, let due = reminder.due {
                    Text(DateFormats.string(due, template: Calendar.current.isDateInToday(due) ? "jmm" : "MMMdjmm"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(reminder.isOverdue ? Color.red : Color.secondary)
                }
            }
        }
    }
}

// MARK: - Focus timer

enum FocusKeys {
    static let focusMinutes = ConfigKey("focusMinutes", 25)
    static let breakMinutes = ConfigKey("breakMinutes", 5)
    static let notify = ConfigKey("notify", true)
}

final class FocusTimerState: ObservableObject {
    enum Phase {
        case focus, rest
        var label: String { self == .focus ? "Focus" : "Break" }
    }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var completedToday = 0

    private var endDate: Date?
    private var timer: Timer?
    var focusMinutes = 25
    var breakMinutes = 5
    var notify = true

    var total: TimeInterval { Double(phase == .focus ? focusMinutes : breakMinutes) * 60 }
    var progress: Double { total > 0 ? 1 - remaining / total : 0 }

    func configure(focus: Int, rest: Int, notify: Bool) {
        let changed = focus != focusMinutes || rest != breakMinutes
        focusMinutes = max(1, focus)
        breakMinutes = max(1, rest)
        self.notify = notify
        if changed && !isRunning { remaining = total }
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if notify { Self.requestNotificationPermission() }
    }

    func pause() {
        tick()
        isRunning = false
        timer?.invalidate()
        timer = nil
        endDate = nil
    }

    func reset() {
        pause()
        phase = .focus
        remaining = total
    }

    func skip() {
        let wasRunning = isRunning
        pause()
        phase = phase == .focus ? .rest : .focus
        remaining = total
        if wasRunning { start() }
    }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finishPhase() }
    }

    private func finishPhase() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        endDate = nil
        if phase == .focus { completedToday += 1 }
        NSSound(named: "Glass")?.play()
        if notify {
            Self.sendNotification(title: phase == .focus ? "Focus session complete" : "Break's over",
                                  body: phase == .focus ? "Nice work! Take a \(breakMinutes)-minute break." : "Ready for another focus session?")
        }
        phase = phase == .focus ? .rest : .focus
        remaining = total
    }

    private static func requestNotificationPermission() {
        guard Shell.isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func sendNotification(title: String, body: String) {
        guard Shell.isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

struct FocusTimerWidget: View {
    @ObservedObject var model: WidgetModel
    @StateObject private var timer = FocusTimerState()
    @Environment(\.widgetStyle) private var style

    private var color: Color { style.tone(timer.phase == .focus ? .red : .green) }

    private var timeText: String {
        let seconds = Int(timer.remaining.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        Group {
            switch model.family {
            case .small, .large: small
            case .medium: medium
            }
        }
        .onAppear(perform: configure)
        .onChange(of: model.config) { _, _ in configure() }
    }

    private func configure() {
        timer.configure(focus: model[FocusKeys.focusMinutes], rest: model[FocusKeys.breakMinutes], notify: model[FocusKeys.notify])
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(action: timer.reset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            Button(action: timer.toggle) {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(color))
            }
            Button(action: timer.skip) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
        }
        .buttonStyle(WidgetButtonStyle())
    }

    private var ring: some View {
        RingGauge(value: timer.progress, color: color, lineWidth: 7) {
            VStack(spacing: 0) {
                Text(timeText)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(timer.phase.label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
            }
        }
    }

    private var small: some View {
        VStack(spacing: 8) {
            ring.frame(width: 92, height: 92)
            controls
        }
        .widgetPadding(12)
    }

    private var medium: some View {
        HStack(spacing: 18) {
            ring.frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 8) {
                WidgetHeader(title: "Focus Timer", symbol: "timer", color: .red)
                Text(timer.isRunning ? (timer.phase == .focus ? "Stay focused 💪" : "Take a breather") : "Ready when you are")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(timer.completedToday) session\(timer.completedToday == 1 ? "" : "s") done · \(model[FocusKeys.focusMinutes])/\(model[FocusKeys.breakMinutes]) min")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                controls
            }
        }
        .widgetPadding(16)
    }
}

// MARK: - Sticky note

enum NoteKeys {
    static let text = ConfigKey("text", "")
    static let color = ConfigKey("color", NoteColor.yellow)
    static let fontSize = ConfigKey("fontSize", 14.0)
}

enum NoteColor: String, ConfigOption {
    case yellow, green, blue, pink, purple, gray, widget

    var label: String { self == .widget ? "Widget Style" : rawValue.capitalized }

    var paper: (Color, Color)? {
        switch self {
        case .yellow: return (Color(hex: 0xFFF6B3), Color(hex: 0xFCE97A))
        case .green: return (Color(hex: 0xD9F7C8), Color(hex: 0xB9EBA0))
        case .blue: return (Color(hex: 0xD3E9FF), Color(hex: 0xADD4FB))
        case .pink: return (Color(hex: 0xFFDCE8), Color(hex: 0xFBB9D0))
        case .purple: return (Color(hex: 0xE9DDFF), Color(hex: 0xD2BCFA))
        case .gray: return (Color(hex: 0xF0F0F0), Color(hex: 0xDADADA))
        case .widget: return nil
        }
    }
}

struct NoteWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        let color = model[NoteKeys.color]
        let text = model.binding(NoteKeys.text)
        ZStack(alignment: .topLeading) {
            TextEditor(text: text)
                .font(.system(size: CGFloat(model[NoteKeys.fontSize])))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
            if text.wrappedValue.isEmpty {
                Text("Write something…")
                    .font(.system(size: CGFloat(model[NoteKeys.fontSize])))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
        .padding(12)
        .environment(\.colorScheme, color.paper == nil ? colorSchemeFromEnvironment : .light)
        .widgetBackground(color.paper.map { CustomBackground.gradient($0.0, $0.1) })
    }

    @Environment(\.colorScheme) private var colorSchemeFromEnvironment
}

// MARK: - Weather

enum WeatherKeys {
    static let city = ConfigKey("city", "")
    static let sky = ConfigKey("sky", true)
}

struct WeatherWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var store = WeatherStore.shared
    @Environment(\.widgetContext) private var context

    private var key: String { WeatherStore.key(forCity: model[WeatherKeys.city]) }
    private var isSample: Bool { context == .gallery }
    private var report: WeatherReport? { isSample ? WeatherReport.sample : store.reports[key] }

    var body: some View {
        Group {
            if let report {
                content(report)
                    .environment(\.colorScheme, model[WeatherKeys.sky] ? .dark : colorSchemeFromEnvironment)
                    .widgetBackground(model[WeatherKeys.sky] ? CustomBackground.sky(code: report.code, isDay: report.isDay) : nil)
            } else if let error = store.errors[key] {
                WidgetMessage(symbol: "location.slash", title: "Weather unavailable", detail: error,
                              actionTitle: "Try Again") { store.refresh(key) }
            } else {
                WidgetMessage(symbol: "cloud.sun", title: "Loading weather…")
            }
        }
        .onAppear { if !isSample { store.retain(key) } }
        .onDisappear { if !isSample { store.release(key) } }
        .onChange(of: key) { old, new in
            guard !isSample else { return }
            store.release(old)
            store.retain(new)
        }
    }

    @Environment(\.colorScheme) private var colorSchemeFromEnvironment

    private func temp(_ celsius: Double) -> String { Fmt.temperature(celsius: celsius) }

    private func symbol(_ code: Int, _ isDay: Bool, size: CGFloat) -> some View {
        Image(systemName: WeatherCode.symbol(code, isDay: isDay))
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size))
    }

    private func currentBlock(_ report: WeatherReport, large: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Text(report.place)
                    .font(.system(size: large ? 16 : 14, weight: .semibold))
                    .lineLimit(1)
                if model[WeatherKeys.city].isEmpty {
                    Image(systemName: "location.fill").font(.system(size: 9))
                }
            }
            Text(temp(report.temperature))
                .font(.system(size: large ? 52 : 42, weight: .light))
                .monospacedDigit()
            Spacer(minLength: 0)
            symbol(report.code, report.isDay, size: 16)
            Text(WeatherCode.description(report.code))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text("H:\(temp(report.high)) L:\(temp(report.low))")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }

    private func hourly(_ report: WeatherReport, count: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(report.hours.prefix(count)) { hour in
                VStack(spacing: 6) {
                    Text(hour.id == report.hours.first?.id ? "Now" : DateFormats.string(hour.date, template: "j"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    symbol(hour.code, hour.isDay, size: 17)
                        .frame(height: 22)
                    Text(temp(hour.temperature))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func content(_ report: WeatherReport) -> some View {
        switch model.family {
        case .small where model.size == .tall:
            // Now on top, the next few hours down the middle, today's range at the bottom.
            VStack(alignment: .leading, spacing: 6) {
                Text(report.place).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(temp(report.temperature)).font(.system(size: 40, weight: .light)).monospacedDigit()
                ForEach(report.hours.dropFirst().prefix(5)) { hour in
                    HStack(spacing: 6) {
                        Text(DateFormats.string(hour.date, template: "j"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .leading)
                        symbol(hour.code, hour.isDay, size: 14).frame(width: 22)
                        Spacer(minLength: 0)
                        Text(temp(hour.temperature)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                    .frame(maxHeight: .infinity)
                }
                Text("H:\(temp(report.high)) L:\(temp(report.low))")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetPadding(16)
        case .small:
            currentBlock(report, large: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .widgetPadding(16)
        case .medium:
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(report.place).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(temp(report.temperature)).font(.system(size: 40, weight: .light)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        symbol(report.code, report.isDay, size: 16)
                        Text(WeatherCode.description(report.code)).font(.system(size: 12, weight: .semibold))
                        Text("H:\(temp(report.high)) L:\(temp(report.low))").font(.system(size: 12, weight: .semibold))
                    }
                }
                Spacer(minLength: 0)
                hourly(report, count: 6)
            }
            .widgetPadding(16)
        case .large:
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(report.place).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Text(temp(report.temperature)).font(.system(size: 48, weight: .light)).monospacedDigit()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        symbol(report.code, report.isDay, size: 18)
                        Text(WeatherCode.description(report.code)).font(.system(size: 13, weight: .semibold))
                        Text("H:\(temp(report.high)) L:\(temp(report.low))").font(.system(size: 13, weight: .semibold))
                        Text("Feels like \(temp(report.apparent))").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                hourly(report, count: 6)
                Divider().overlay(Color.white.opacity(0.3))
                // The portrait shape has room for the whole week.
                DailyForecast(days: Array(report.days.prefix(model.size == .portrait ? 7 : 5)), temp: temp,
                              spacing: model.size == .portrait ? 15 : 6)
                if model.size == .portrait { Spacer(minLength: 0) }
            }
            .widgetPadding(16)
        }
    }
}

private struct DailyForecast: View {
    let days: [WeatherReport.Day]
    let temp: (Double) -> String
    var spacing: CGFloat = 6

    var body: some View {
        let low = days.map(\.low).min() ?? 0
        let high = days.map(\.high).max() ?? 1
        let span = max(high - low, 1)
        VStack(spacing: spacing) {
            ForEach(days) { day in
                HStack(spacing: 8) {
                    Text(Calendar.current.isDateInToday(day.date) ? "Today" : DateFormats.string(day.date, template: "EEE"))
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 46, alignment: .leading)
                    Image(systemName: WeatherCode.symbol(day.code, isDay: true))
                        .symbolRenderingMode(.multicolor)
                        .frame(width: 24)
                    Text(temp(day.low))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                    GeometryReader { geometry in
                        let start = CGFloat((day.low - low) / span) * geometry.size.width
                        let width = max(6, CGFloat((day.high - day.low) / span) * geometry.size.width)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule()
                                .fill(LinearGradient(colors: [.cyan, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                                .frame(width: width)
                                .offset(x: start)
                        }
                    }
                    .frame(height: 5)
                    Text(temp(day.high))
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}

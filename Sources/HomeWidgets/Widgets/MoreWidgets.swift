import SwiftUI
import AppKit

// A dot-matrix clock, a moment from history each day, and battery rings for your Bluetooth gear.

// MARK: - Dot clock

enum DotClockKeys {
    static let color = ConfigKey("dotColor", DotColor.accent)
    static let showSeconds = ConfigKey("showSeconds", false)
    static let use24Hour = ConfigKey("use24Hour", false)
}

enum DotColor: String, ConfigOption {
    case accent, white, red, amber, green, cyan
    var id: String { rawValue }
    var label: String { rawValue == "accent" ? "Accent" : rawValue.capitalized }
    func color(accent: Color) -> Color {
        switch self {
        case .accent: return accent
        case .white: return Color(white: 0.96)
        case .red: return Color(red: 1, green: 0.27, blue: 0.22)
        case .amber: return Color(red: 1, green: 0.7, blue: 0.2)
        case .green: return Color(red: 0.3, green: 0.95, blue: 0.45)
        case .cyan: return Color(red: 0.35, green: 0.9, blue: 1)
        }
    }
}

struct DotClockWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetAccent) private var accent

    /// 5×7 digits, one string of five 0/1 columns per row.
    private static let digits: [[String]] = [
        ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
        ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    ]

    var body: some View {
        // Square sizes stack the hours over the minutes so the digits fill the widget.
        let stacked = model.size == .small || model.size == .large
        let seconds = model[DotClockKeys.showSeconds] && !stacked
        Ticking(everySecond: true) { date in
            let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
            let rawHour = parts.hour ?? 0
            let hour = model[DotClockKeys.use24Hour] ? rawHour : (rawHour % 12 == 0 ? 12 : rawHour % 12)
            let colonOn = (parts.second ?? 0) % 2 == 0 || seconds
            let lit = model[DotClockKeys.color].color(accent: accent)
            let grid = stacked
                ? Self.stacked(hour: hour, minute: parts.minute ?? 0)
                : Self.columns(hour: hour, minute: parts.minute ?? 0, second: seconds ? parts.second : nil, colon: colonOn,
                               leadingZero: model[DotClockKeys.use24Hour])
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                Canvas { context, size in
                    Self.draw(grid, in: &context, size: size, lit: lit)
                }
                .aspectRatio(CGFloat(grid.count) / CGFloat(grid.first?.count ?? 7), contentMode: .fit)
                if model.family != .small {
                    HStack {
                        Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                        Spacer()
                        if !model[DotClockKeys.use24Hour] { Text(rawHour < 12 ? "AM" : "PM") }
                    }
                    .font(.system(size: model.family == .large ? 14 : 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(lit.opacity(0.75))
                } else {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(lit.opacity(0.75))
                }
                Spacer(minLength: 0)
            }
            .widgetPadding(model.family == .small ? 12 : 16)
        }
    }

    /// Two digits of hours above two of minutes, one array of 15 booleans per dot column.
    private static func stacked(hour: Int, minute: Int) -> [[Bool]] {
        func pair(_ value: Int, x: Int) -> [Bool] {
            let digit = x < 5 ? value / 10 : value % 10
            let column = x < 5 ? x : x - 6
            return (0..<7).map { y in x == 5 ? false : Array(digits[digit][y])[column] == "1" }
        }
        return (0..<11).map { x in pair(hour, x: x) + [false] + pair(minute, x: x) }
    }

    /// The lit pattern, one array of 7 booleans per dot column.
    private static func columns(hour: Int, minute: Int, second: Int?, colon: Bool, leadingZero: Bool) -> [[Bool]] {
        var out: [[Bool]] = []
        func digit(_ value: Int?) {
            for x in 0..<5 {
                out.append((0..<7).map { y in
                    guard let value else { return false }
                    return Array(digits[value][y])[x] == "1"
                })
            }
        }
        func gap() { out.append(Array(repeating: false, count: 7)) }
        func separator() { out.append((0..<7).map { colon && ($0 == 2 || $0 == 4) }) }
        digit(hour < 10 && !leadingZero ? nil : hour / 10)
        gap()
        digit(hour % 10)
        gap()
        separator()
        gap()
        digit(minute / 10)
        gap()
        digit(minute % 10)
        if let second {
            gap()
            separator()
            gap()
            digit(second / 10)
            gap()
            digit(second % 10)
        }
        return out
    }

    private static func draw(_ columns: [[Bool]], in context: inout GraphicsContext, size: CGSize, lit: Color) {
        let rows = CGFloat(columns.first?.count ?? 7)
        let cell = min(size.width / CGFloat(columns.count), size.height / rows)
        let originX = (size.width - cell * CGFloat(columns.count)) / 2
        let originY = (size.height - cell * rows) / 2
        let radius = cell * 0.38
        for (x, column) in columns.enumerated() {
            for (y, on) in column.enumerated() {
                let center = CGPoint(x: originX + (CGFloat(x) + 0.5) * cell, y: originY + (CGFloat(y) + 0.5) * cell)
                let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                if on {
                    // A soft glow behind each lit dot, like an LED.
                    let glow = Path(ellipseIn: CGRect(x: center.x - radius * 1.6, y: center.y - radius * 1.6, width: radius * 3.2, height: radius * 3.2))
                    context.fill(glow, with: .color(lit.opacity(0.16)))
                    context.fill(dot, with: .color(lit))
                } else {
                    context.fill(dot, with: .color(Color.primary.opacity(0.07)))
                }
            }
        }
    }
}

// MARK: - On this day

final class OnThisDayService: ObservableObject {
    static let shared = OnThisDayService()

    struct Event: Identifiable, Equatable {
        let year: Int
        let text: String
        let link: URL?
        var id: String { "\(year)-\(text.prefix(24))" }
    }

    @Published private(set) var events: [Event] = []
    @Published private(set) var failed = false
    private var loadedDay = ""
    private var loading = false

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return String(format: "%02d/%02d", parts.month ?? 1, parts.day ?? 1)
    }

    /// Wikipedia's selected events for today; fetched once a day.
    func loadIfNeeded(for date: Date = Date()) {
        let key = Self.dayKey(date)
        guard key != loadedDay, !loading, let url = URL(string: "https://en.wikipedia.org/api/rest_v1/feed/onthisday/selected/\(key)") else { return }
        loading = true
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("HomeWidgets/3 (macOS desktop widgets)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            let parsed = data.map(Self.parse) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.failed = parsed.isEmpty
                if !parsed.isEmpty {
                    self.events = parsed
                    self.loadedDay = key
                }
            }
        }.resume()
    }

    static func parse(_ data: Data) -> [Event] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selected = root["selected"] as? [[String: Any]] else { return [] }
        return selected.compactMap { item in
            guard let year = item["year"] as? Int, let text = item["text"] as? String else { return nil }
            let page = (item["pages"] as? [[String: Any]])?.first
            let link = ((page?["content_urls"] as? [String: Any])?["desktop"] as? [String: Any])?["page"] as? String
            return Event(year: year, text: text, link: link.flatMap(URL.init(string:)))
        }
    }

    static let sample: [Event] = [
        Event(year: 1947, text: "Chuck Yeager flies the Bell X-1 faster than the speed of sound, the first person to do so in level flight.", link: nil),
        Event(year: 1066, text: "William the Conqueror's Norman army defeats the English at the Battle of Hastings.", link: nil),
        Event(year: 1962, text: "A U-2 spy plane photographs Soviet missile sites in Cuba, setting off the Cuban Missile Crisis.", link: nil),
        Event(year: 1926, text: "A. A. Milne's children's book Winnie-the-Pooh is first published.", link: nil),
    ]
}

struct OnThisDayWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = OnThisDayService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style
    @State private var offset = 0

    var body: some View {
        let events = context == .gallery ? OnThisDayService.sample : service.events
        Ticking(everySecond: false) { date in
            Group {
                if events.isEmpty {
                    WidgetMessage(symbol: "clock.arrow.circlepath", title: service.failed ? "Couldn't load history" : "Loading…",
                                  detail: service.failed ? "Check your internet connection." : nil)
                } else {
                    content(events, date: date)
                }
            }
            .task(id: OnThisDayService.dayKey(date)) {
                if context == .desktop { service.loadIfNeeded(for: date) }
            }
        }
    }

    @ViewBuilder
    private func content(_ events: [OnThisDayService.Event], date: Date) -> some View {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 0
        let start = (day + offset) % events.count
        let brown = style.tone(.brown)
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "On This Day", symbol: "clock.arrow.circlepath", color: .brown,
                         trailing: model.family == .small || model.size == .tall ? nil : date.formatted(.dateTime.month(.abbreviated).day()))
            if model.family == .large || model.size == .tall {
                let count = model.size == .tall ? 3 : 4
                ForEach(0..<min(count, events.count), id: \.self) { i in
                    let event = events[(start + i) % events.count]
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(event.year)).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(brown)
                            .frame(width: 46, alignment: .leading)
                        Text(event.text).font(.system(size: 12.5)).lineLimit(3)
                    }
                    .onTapGesture { open(event) }
                }
                Spacer(minLength: 0)
            } else {
                let event = events[start]
                let wide = model.size == .wide
                if wide {
                    HStack(alignment: .center, spacing: 16) {
                        Text(String(event.year)).font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(brown)
                        Text(event.text).font(.system(size: 15, weight: .medium)).lineLimit(3)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Text(String(event.year))
                        .font(.system(size: model.family == .small ? 26 : 30, weight: .bold, design: .rounded))
                        .foregroundStyle(brown)
                    Text(event.text)
                        .font(.system(size: model.family == .small ? 11.5 : 15, weight: .medium))
                        .lineLimit(model.family == .small ? 5 : 4)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                }
            }
        }
        .widgetPadding()
        .contentShape(Rectangle())
        .onTapGesture { offset += 1 }
        .contextMenu {
            if let link = events[start].link {
                Button("Read on Wikipedia") { NSWorkspace.shared.open(link) }
            }
        }
        .help("Click for another moment from history")
    }

    private func open(_ event: OnThisDayService.Event) {
        if let link = event.link { NSWorkspace.shared.open(link) } else { offset += 1 }
    }
}

// MARK: - Device batteries

final class DeviceBatteryMonitor: PollingMonitor {
    static let shared = DeviceBatteryMonitor()

    struct Device: Identifiable, Equatable {
        let name: String
        let symbol: String
        let level: Double
        var caseLevel: Double? = nil
        var charging = false
        var id: String { name }
    }

    @Published private(set) var devices: [Device] = []
    override var interval: TimeInterval { 120 }

    override func sample() {
        Shell.output("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]) { [weak self] text in
            guard let self else { return }
            let found = Self.parse(text ?? "")
            if found != self.devices { self.devices = found }
        }
    }

    /// Connected Bluetooth devices that report a battery level.
    static func parse(_ text: String) -> [Device] {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var out: [Device] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let props = value as? [String: Any] else { continue }
                    func percent(_ key: String) -> Double? {
                        guard let raw = props[key] as? String else { return nil }
                        return Double(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)).map { $0 / 100 }
                    }
                    let left = percent("device_batteryLevelLeft"), right = percent("device_batteryLevelRight")
                    guard let level = percent("device_batteryLevelMain") ?? [left, right].compactMap({ $0 }).min() else { continue }
                    let kind = props["device_minorType"] as? String ?? ""
                    out.append(Device(name: name, symbol: symbol(name: name, kind: kind, earbuds: left != nil || right != nil),
                                      level: level, caseLevel: percent("device_batteryLevelCase")))
                }
            }
        }
        return out.sorted { $0.name < $1.name }
    }

    private static func symbol(name: String, kind: String, earbuds: Bool) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if earbuds || lower.contains("airpods") { return "airpodspro" }
        switch kind {
        case "Headphones", "Headset": return "headphones"
        case "Mouse": return "computermouse.fill"
        case "Keyboard": return "keyboard.fill"
        case "Gamepad": return "gamecontroller.fill"
        case "Trackpad": return "hand.point.up.left.fill"
        default: return "wave.3.right"
        }
    }

    static let sample: [Device] = [
        Device(name: "MacBook Pro", symbol: "laptopcomputer", level: 0.52, charging: true),
        Device(name: "AirPods Pro", symbol: "airpodspro", level: 1, caseLevel: 0.28),
        Device(name: "Magic Mouse", symbol: "computermouse.fill", level: 0.64),
        Device(name: "Keyboard", symbol: "keyboard.fill", level: 0.18),
    ]
}

struct DeviceBatteriesWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var monitor = DeviceBatteryMonitor.shared
    @ObservedObject private var battery = BatteryMonitor.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var items: [DeviceBatteryMonitor.Device] {
        if context == .gallery { return DeviceBatteryMonitor.sample }
        var list: [DeviceBatteryMonitor.Device] = []
        if battery.hasBattery {
            list.append(.init(name: Host.current().localizedName ?? "Mac", symbol: "laptopcomputer", level: battery.level, charging: battery.isCharging))
        }
        return list + monitor.devices
    }

    var body: some View {
        let items = self.items
        Group {
            if items.isEmpty {
                WidgetMessage(symbol: "battery.100percent", title: "No batteries", detail: "Connect AirPods, a mouse or a keyboard.")
            } else if model.family == .large {
                VStack(alignment: .leading, spacing: 10) {
                    WidgetHeader(title: "Batteries", symbol: "battery.75percent", color: .green)
                    ForEach(items.prefix(6)) { row($0) }
                    Spacer(minLength: 0)
                }
                .widgetPadding()
            } else {
                let shown = Array(items.prefix(4))
                let columns = model.family == .small ? min(2, shown.count) : shown.count
                GeometryReader { geometry in
                    let rows = model.family == .small && shown.count > 2 ? 2 : 1
                    let side = min(geometry.size.width / CGFloat(columns), geometry.size.height / CGFloat(rows) - (model.family == .small ? 0 : 18))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
                        ForEach(shown) { device in
                            VStack(spacing: 4) {
                                ring(device, size: side * 0.86)
                                if model.family != .small {
                                    Text("\(Int((device.level * 100).rounded()))%").font(.system(size: 13, weight: .semibold, design: .rounded))
                                }
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .widgetPadding(model.family == .small ? 12 : Layout.padding)
            }
        }
        .monitoring(if: context == .desktop, monitor, battery)
    }

    private func color(_ device: DeviceBatteryMonitor.Device) -> Color {
        device.level <= 0.2 && !device.charging ? .red : .green
    }

    private func ring(_ device: DeviceBatteryMonitor.Device, size: CGFloat) -> some View {
        RingGauge(value: device.level, color: color(device), lineWidth: max(4, size * 0.09)) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: device.symbol)
                    .font(.system(size: size * 0.3, weight: .medium))
                if device.charging {
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.16, weight: .bold)).foregroundStyle(style.tone(.green))
                        .offset(x: size * 0.1, y: -size * 0.08)
                }
            }
        }
        .frame(width: size, height: size)
        .help("\(device.name): \(Int((device.level * 100).rounded()))%")
    }

    private func row(_ device: DeviceBatteryMonitor.Device) -> some View {
        HStack(spacing: 10) {
            Image(systemName: device.symbol).font(.system(size: 17)).frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if device.charging { Image(systemName: "bolt.fill").font(.system(size: 10)).foregroundStyle(style.tone(.green)) }
                    Spacer()
                    Text("\(Int((device.level * 100).rounded()))%").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                BarMeter(value: device.level, color: color(device))
                if let caseLevel = device.caseLevel {
                    Text("Case \(Int((caseLevel * 100).rounded()))%").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

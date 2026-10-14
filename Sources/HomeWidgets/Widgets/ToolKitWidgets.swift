import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreServices
import UniformTypeIdentifiers
import UserNotifications

// Practical everyday tools: timer, web search, dictionary, unit converter,
// QR codes, passwords, a colour picker, recent files and screenshots.

/// Posts a banner (when the app is installed) — shared by the timer and friends.
enum Notify {
    static func requestPermission() {
        guard Shell.isBundled else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        guard Shell.isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

/// A small "Copied" flash used by several tools.
private struct CopiedBadge: View {
    let visible: Bool
    var body: some View {
        if visible {
            Label("Copied", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
                .transition(.scale.combined(with: .opacity))
        }
    }
}

private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Timer

enum TimerKeys {
    static let presets = ConfigKey("presets", "1, 3, 5, 10, 15, 25")
    static let label = ConfigKey("label", "Timer")
    static let end = ConfigKey("end", Date.distantPast)
    static let total = ConfigKey("total", 300)
    static let pausedLeft = ConfigKey("pausedLeft", 0)
    static let sound = ConfigKey("sound", "Glass")
}

/// Fires timers even while their widget is hidden or covered.
@MainActor
final class TimerCenter {
    static let shared = TimerCenter()
    private var work: [UUID: DispatchWorkItem] = [:]

    func schedule(_ model: WidgetModel) {
        work[model.id]?.cancel()
        let end = model[TimerKeys.end]
        guard end > Date() else { return }
        let item = DispatchWorkItem { [weak model] in
            guard let model else { return }
            MainActor.assumeIsolated {
                NSSound(named: NSSound.Name(model[TimerKeys.sound]))?.play()
                Notify.post("\(model[TimerKeys.label]) done", "Your \(Fmt.duration(minutes: max(1, model[TimerKeys.total] / 60))) timer finished.")
                model.config[TimerKeys.end] = .distantPast
                model.config[TimerKeys.pausedLeft] = 0
            }
        }
        work[model.id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + end.timeIntervalSinceNow, execute: item)
    }

    func cancel(_ id: UUID) {
        work[id]?.cancel()
        work[id] = nil
    }
}

struct TimerWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetIsVisible) private var visible
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetContext) private var context

    private var presets: [Int] {
        model[TimerKeys.presets].split(whereSeparator: { ",; ".contains($0) }).compactMap { Int($0) }.filter { $0 > 0 && $0 <= 600 }.prefix(6).map { $0 }
    }

    private var running: Bool { model[TimerKeys.end] > Date() }
    private var paused: Bool { !running && model[TimerKeys.pausedLeft] > 0 }

    private func remaining(at date: Date) -> Int {
        if running { return max(0, Int(ceil(model[TimerKeys.end].timeIntervalSince(date)))) }
        if paused { return model[TimerKeys.pausedLeft] }
        return context == .gallery ? 272 : model[TimerKeys.total]
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let left = remaining(at: running && visible ? timeline.date : Date())
            let total = max(1, model[TimerKeys.total])
            let tone = style.tone(.orange)
            HStack(spacing: 12) {
                Button(action: toggle) {
                    RingGauge(value: Double(left) / Double(total), color: .orange, lineWidth: model.family == .small ? 8 : 7) {
                        VStack(spacing: 0) {
                            Text(Self.format(left))
                                .font(.system(size: model.family == .small ? 26 : 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .fitLine(0.5)
                            Image(systemName: running ? "pause.fill" : "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(tone)
                        }
                    }
                }
                .buttonStyle(WidgetButtonStyle())
                if model.family != .small {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model[TimerKeys.label]).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 5)], spacing: 5) {
                            ForEach(presets, id: \.self) { minutes in
                                Button { start(minutes * 60) } label: {
                                    Text("\(minutes)m")
                                        .font(.system(size: 11, weight: .semibold))
                                        .frame(maxWidth: .infinity, minHeight: 24)
                                        .background(Capsule().fill(tone.opacity(0.16)))
                                }
                                .buttonStyle(WidgetButtonStyle())
                            }
                        }
                        HStack(spacing: 8) {
                            Button("+1 min") { add(60) }
                            Button("Reset", action: reset)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(WidgetButtonStyle())
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .widgetPadding()
        }
        .contextMenu {
            ForEach(presets, id: \.self) { minutes in Button("\(minutes) minutes") { start(minutes * 60) } }
        }
        .onAppear {
            if context == .desktop && running { TimerCenter.shared.schedule(model) }
        }
    }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds / 60) % 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func start(_ seconds: Int) {
        Notify.requestPermission()
        model.config[TimerKeys.total] = seconds
        model.config[TimerKeys.pausedLeft] = 0
        model.config[TimerKeys.end] = Date().addingTimeInterval(TimeInterval(seconds))
        TimerCenter.shared.schedule(model)
    }

    private func toggle() {
        guard context == .desktop else { return }
        if running {
            model.config[TimerKeys.pausedLeft] = remaining(at: Date())
            model.config[TimerKeys.end] = .distantPast
            TimerCenter.shared.cancel(model.id)
        } else if paused {
            model.config[TimerKeys.end] = Date().addingTimeInterval(TimeInterval(model[TimerKeys.pausedLeft]))
            model.config[TimerKeys.pausedLeft] = 0
            TimerCenter.shared.schedule(model)
        } else {
            start(model[TimerKeys.total])
        }
    }

    private func add(_ seconds: Int) {
        if running {
            model.config[TimerKeys.end] = model[TimerKeys.end].addingTimeInterval(TimeInterval(seconds))
            model.config[TimerKeys.total] = model[TimerKeys.total] + seconds
            TimerCenter.shared.schedule(model)
        } else if paused {
            model.config[TimerKeys.pausedLeft] = model[TimerKeys.pausedLeft] + seconds
            model.config[TimerKeys.total] = model[TimerKeys.total] + seconds
        } else {
            model.config[TimerKeys.total] = model[TimerKeys.total] + seconds
        }
    }

    private func reset() {
        TimerCenter.shared.cancel(model.id)
        model.config[TimerKeys.end] = .distantPast
        model.config[TimerKeys.pausedLeft] = 0
    }
}

// MARK: - Web search

enum SearchEngine: String, ConfigOption {
    case google, duckDuckGo, bing, youtube, wikipedia, github, claude, maps

    var label: String {
        switch self {
        case .google: return "Google"
        case .duckDuckGo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .youtube: return "YouTube"
        case .wikipedia: return "Wikipedia"
        case .github: return "GitHub"
        case .claude: return "Claude"
        case .maps: return "Apple Maps"
        }
    }

    var symbol: String {
        switch self {
        case .google, .duckDuckGo, .bing: return "magnifyingglass"
        case .youtube: return "play.rectangle.fill"
        case .wikipedia: return "book.fill"
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "sparkles"
        case .maps: return "map.fill"
        }
    }

    func url(for query: String) -> URL? {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        switch self {
        case .google: return URL(string: "https://www.google.com/search?q=\(q)")
        case .duckDuckGo: return URL(string: "https://duckduckgo.com/?q=\(q)")
        case .bing: return URL(string: "https://www.bing.com/search?q=\(q)")
        case .youtube: return URL(string: "https://www.youtube.com/results?search_query=\(q)")
        case .wikipedia: return URL(string: "https://en.wikipedia.org/w/index.php?search=\(q)")
        case .github: return URL(string: "https://github.com/search?q=\(q)")
        case .claude: return URL(string: "https://claude.ai/new?q=\(q)")
        case .maps: return URL(string: "maps://?q=\(q)")
        }
    }
}

enum SearchKeys {
    static let engine = ConfigKey("engine", SearchEngine.google)
}

struct WebSearchWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @State private var query = ""

    var body: some View {
        let engine = model[SearchKeys.engine]
        let roomy = model.family != .small
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Search", symbol: engine.symbol, color: .blue, trailing: engine.label)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(engine.label)…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: roomy ? 15 : 13))
                    .onSubmit { go(engine) }
                    .disabled(context != .desktop)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, roomy ? 11 : 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.08)))
            if model.family != .small {
                HStack(spacing: 6) {
                    ForEach([SearchEngine.google, .youtube, .wikipedia, .claude, .maps], id: \.self) { item in
                        Button { model.config[SearchKeys.engine] = item; if !query.isEmpty { go(item) } } label: {
                            Image(systemName: item.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: 52, minHeight: 28)
                                .frame(maxWidth: .infinity)
                                .background(Capsule().fill(item == engine ? Color.blue.opacity(0.25) : Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(WidgetButtonStyle())
                        .help(item.label)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    private func go(_ engine: SearchEngine) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = engine.url(for: text) else { return }
        NSWorkspace.shared.open(url)
        query = ""
    }
}

// MARK: - Dictionary

enum WordBank {
    /// Offline word of the day, so the widget always has something worth reading.
    static let words: [(String, String)] = [
        ("serendipity", "finding something good without looking for it"),
        ("ephemeral", "lasting a very short time"),
        ("resilient", "able to recover quickly from difficulty"),
        ("meticulous", "very careful and precise"),
        ("eloquent", "fluent and persuasive in speaking or writing"),
        ("tenacious", "holding firmly to a goal; persistent"),
        ("candor", "the quality of being open and honest"),
        ("benevolent", "well meaning and kindly"),
        ("pragmatic", "dealing with things sensibly and realistically"),
        ("ubiquitous", "present, appearing or found everywhere"),
        ("diligent", "showing care and effort in one's work"),
        ("magnanimous", "generous or forgiving, especially toward a rival"),
        ("lucid", "clear and easy to understand"),
        ("gregarious", "fond of company; sociable"),
        ("ineffable", "too great to be expressed in words"),
        ("perseverance", "continued effort despite difficulty"),
        ("quintessential", "the most perfect example of a quality"),
        ("sagacious", "having keen judgment; wise"),
        ("vivacious", "attractively lively and animated"),
        ("zealous", "having great energy for a cause"),
        ("audacious", "showing a willingness to take bold risks"),
        ("cogent", "clear, logical and convincing"),
        ("equanimity", "calmness, especially in a difficult situation"),
        ("fortitude", "courage in pain or adversity"),
        ("gratitude", "the quality of being thankful"),
        ("humility", "a modest view of one's own importance"),
        ("integrity", "being honest and having strong moral principles"),
        ("jubilant", "feeling or expressing great happiness"),
        ("kindred", "similar in kind; related"),
        ("luminous", "full of or shedding light"),
    ]

    static func today(offset: Int = 0) -> (String, String) {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return words[((day + offset) % words.count + words.count) % words.count]
    }
}

struct DictionaryWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @State private var word = ""
    @State private var definition: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Dictionary", symbol: "character.book.closed.fill", color: .brown)
            HStack(spacing: 6) {
                TextField("Look up a word…", text: $word)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .onSubmit(lookUp)
                    .disabled(context != .desktop)
                if !word.isEmpty {
                    Button { word = ""; definition = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(WidgetButtonStyle())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.08)))
            if let definition {
                ScrollView {
                    Text(definition)
                        .font(.system(size: 11.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            } else {
                let (w, meaning) = WordBank.today()
                let big = model.family == .large || model.size == .tall
                if !big { Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: big ? 4 : 2) {
                    Text("Word of the day").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Text(w)
                        .font(.system(size: model.family == .small ? (big ? 24 : 17) : (big ? 34 : 24), weight: .semibold, design: .serif))
                        .fitLine()
                    Text(meaning).font(.system(size: big ? 13 : 11.5)).foregroundStyle(.secondary).lineLimit(3)
                }
                .onTapGesture { word = w; lookUp() }
                // Tall and large widgets have room for the full dictionary entry.
                if big, let entry = Self.entry(for: w) {
                    Divider().opacity(0.5)
                    Text(entry)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    private static func entry(for word: String) -> String? {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let found = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String? else { return nil }
        return tidy(found)
    }

    private func lookUp() {
        let text = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { definition = nil; return }
        let range = CFRange(location: 0, length: (text as NSString).length)
        if let found = DCSCopyTextDefinition(nil, text as CFString, range)?.takeRetainedValue() as String? {
            definition = Self.tidy(found)
        } else {
            definition = "No definition found for “\(text)”."
        }
    }

    /// The system dictionary returns one long line; break it at the numbered senses.
    private static func tidy(_ raw: String) -> String {
        raw.replacingOccurrences(of: #" (\d+) "#, with: "\n$1. ", options: .regularExpression)
            .replacingOccurrences(of: " | ", with: "\n")
    }
}

// MARK: - Unit converter

enum ConverterCategory: String, ConfigOption {
    case length, mass, temperature, volume, speed, data, time

    var label: String { rawValue.capitalized }

    var units: [(String, Dimension)] {
        switch self {
        case .length: return [("mm", UnitLength.millimeters), ("cm", UnitLength.centimeters), ("m", UnitLength.meters), ("km", UnitLength.kilometers),
                              ("in", UnitLength.inches), ("ft", UnitLength.feet), ("yd", UnitLength.yards), ("mi", UnitLength.miles)]
        case .mass: return [("g", UnitMass.grams), ("kg", UnitMass.kilograms), ("oz", UnitMass.ounces), ("lb", UnitMass.pounds), ("st", UnitMass.stones)]
        case .temperature: return [("°F", UnitTemperature.fahrenheit), ("°C", UnitTemperature.celsius), ("K", UnitTemperature.kelvin)]
        case .volume: return [("mL", UnitVolume.milliliters), ("L", UnitVolume.liters), ("tsp", UnitVolume.teaspoons), ("tbsp", UnitVolume.tablespoons),
                              ("cup", UnitVolume.cups), ("fl oz", UnitVolume.fluidOunces), ("gal", UnitVolume.gallons)]
        case .speed: return [("mph", UnitSpeed.milesPerHour), ("km/h", UnitSpeed.kilometersPerHour), ("m/s", UnitSpeed.metersPerSecond), ("kn", UnitSpeed.knots)]
        case .data: return [("KB", UnitInformationStorage.kilobytes), ("MB", UnitInformationStorage.megabytes), ("GB", UnitInformationStorage.gigabytes),
                            ("TB", UnitInformationStorage.terabytes), ("Mb", UnitInformationStorage.megabits), ("Gb", UnitInformationStorage.gigabits)]
        case .time: return [("sec", UnitDuration.seconds), ("min", UnitDuration.minutes), ("hr", UnitDuration.hours)]
        }
    }
}

enum ConverterKeys {
    static let category = ConfigKey("category", ConverterCategory.length)
    static let from = ConfigKey("from", 0)
    static let to = ConfigKey("to", 5)
    static let value = ConfigKey("value", "1")
}

struct ConverterWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let category = model[ConverterKeys.category]
        let units = category.units
        let from = min(model[ConverterKeys.from], units.count - 1)
        let to = min(model[ConverterKeys.to], units.count - 1)
        let input = Double(model[ConverterKeys.value].replacingOccurrences(of: ",", with: "")) ?? 0
        let result = Measurement(value: input, unit: units[from].1).converted(to: units[to].1).value
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    ForEach(ConverterCategory.allCases) { item in
                        Button(item.label) {
                            model.config[ConverterKeys.category] = item
                            model.config[ConverterKeys.from] = 0
                            model.config[ConverterKeys.to] = min(1, item.units.count - 1)
                        }
                    }
                } label: {
                    Label(category.label, systemImage: "arrow.left.arrow.right").font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .foregroundStyle(style.tone(.teal))
                Spacer()
                Button {
                    model.config[ConverterKeys.from] = to
                    model.config[ConverterKeys.to] = from
                } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(WidgetButtonStyle())
                    .help("Swap")
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                TextField("1", text: model.binding(ConverterKeys.value))
                    .textFieldStyle(.plain)
                    .font(.system(size: model.family == .small ? 20 : 24, weight: .semibold, design: .rounded))
                unitMenu(units, selected: from) { model.config[ConverterKeys.from] = $0 }
            }
            Divider().opacity(0.4)
            HStack(spacing: 6) {
                Text(Self.format(result))
                    .font(.system(size: model.family == .small ? 22 : 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.tone(.teal))
                    .fitLine(0.5)
                    .textSelection(.enabled)
                Spacer(minLength: 2)
                unitMenu(units, selected: to) { model.config[ConverterKeys.to] = $0 }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    private func unitMenu(_ units: [(String, Dimension)], selected: Int, pick: @escaping (Int) -> Void) -> some View {
        Menu {
            ForEach(units.indices, id: \.self) { index in Button(units[index].0) { pick(index) } }
        } label: {
            Text(units[selected].0).font(.system(size: 12, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumSignificantDigits = 7
        formatter.usesSignificantDigits = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - QR code

enum QRKeys {
    static let text = ConfigKey("text", "")
}

struct QRCodeWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @State private var copied = false

    private var content: String {
        let text = model[QRKeys.text].trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        if context == .gallery { return "https://github.com/ProffesorDiggamore/MacOS-Home" }
        return NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600).description ?? ""
    }

    var body: some View {
        let text = content
        VStack(spacing: 6) {
            if let image = Self.image(for: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(1, contentMode: .fit)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white))
                    .onTapGesture { copy(image) }
                    .onDrag { NSItemProvider(object: image) }
                    .help("Click to copy the QR code · drag it into a document")
            } else {
                WidgetMessage(symbol: "qrcode", title: "Copy a link", detail: "The QR code shows whatever text or link is on your clipboard.")
            }
            if model.family != .small {
                TextField("Text or link (empty = clipboard)", text: model.binding(QRKeys.text))
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
            }
        }
        .overlay(alignment: .bottom) { CopiedBadge(visible: copied) }
        .animation(.spring(duration: 0.25), value: copied)
        .widgetPadding(10)
    }

    private func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func image(for text: String) -> NSImage? {
        guard !text.isEmpty else { return nil }
        if let cached = cache.object(forKey: text as NSString) { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        cache.setObject(image, forKey: text as NSString)
        return image
    }
}

// MARK: - Password generator

enum PasswordKeys {
    static let length = ConfigKey("length", 18)
    static let symbols = ConfigKey("symbols", true)
    static let memorable = ConfigKey("memorable", false)
}

struct PasswordWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style
    @State private var password = ""
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Password", symbol: "key.fill", color: .green, trailing: strengthLabel)
            Spacer(minLength: 0)
            Text(password.isEmpty ? " " : password)
                .contentTransition(.opacity)
                .font(.system(size: model.family == .small ? 15 : 21, weight: .medium, design: .monospaced))
                .lineLimit(model.family == .small ? 3 : 2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: copy)
                .help("Click to copy")
            Capsule().fill(Color.primary.opacity(0.1)).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule().fill(style.tone(strengthColor)).frame(width: proxy.size.width * strength)
                    }
                }
            Spacer(minLength: 0)
            HStack {
                Button { password = generate() } label: { Label("New", systemImage: "arrow.clockwise") }
                Spacer()
                Button(action: copy) { Label("Copy", systemImage: "doc.on.doc") }
            }
            .font(.system(size: 11.5, weight: .semibold))
            .buttonStyle(WidgetButtonStyle())
        }
        .overlay { CopiedBadge(visible: copied) }
        .animation(.spring(duration: 0.25), value: copied)
        .widgetPadding()
        .onAppear { if password.isEmpty { password = generate() } }
        .onChange(of: model.config) { _, _ in password = generate() }
    }

    private var strength: Double {
        let pool: Double = model[PasswordKeys.memorable] ? 11 : (model[PasswordKeys.symbols] ? 6.5 : 5.95) // bits per unit
        let units = model[PasswordKeys.memorable] ? Double(password.split(separator: "-").count) : Double(password.count)
        return min(1, units * pool / 100)
    }

    private var strengthColor: Color { strength > 0.75 ? .green : strength > 0.5 ? .yellow : .red }
    private var strengthLabel: String { strength > 0.75 ? "Strong" : strength > 0.5 ? "Okay" : "Weak" }

    /// Copies, then swaps in a fresh password so the same one is never pasted twice.
    private func copy() {
        copyToClipboard(password)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeInOut(duration: 0.25)) { password = generate() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }

    private static let syllables = ["ba", "ko", "ri", "ta", "mu", "ne", "lo", "sa", "vi", "de", "po", "ka", "lu", "mi", "zo", "fe", "ra", "ti", "no", "gu"]

    private func generate() -> String {
        if model[PasswordKeys.memorable] {
            let words = (0..<5).map { _ in (0..<3).map { _ in Self.syllables[Self.random(Self.syllables.count)] }.joined() }
            return words.joined(separator: "-") + String(Self.random(90) + 10)
        }
        var pool = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        if model[PasswordKeys.symbols] { pool += Array("!@#$%^&*-_=+?") }
        return String((0..<max(8, min(64, model[PasswordKeys.length]))).map { _ in pool[Self.random(pool.count)] })
    }

    /// Cryptographically secure, unbiased.
    private static func random(_ upper: Int) -> Int {
        var value: UInt32 = 0
        let limit = UInt32.max - UInt32.max % UInt32(upper)
        repeat { _ = SecRandomCopyBytes(kSecRandomDefault, 4, &value) } while value >= limit
        return Int(value % UInt32(upper))
    }
}

// MARK: - Colour picker

enum ColorPickerKeys {
    static let history = ConfigKey<[String]>("history", [])
}

struct ColorPickerWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @State private var copied = false

    private var history: [String] {
        let saved = model[ColorPickerKeys.history]
        return saved.isEmpty && context == .gallery ? ["FF6A88", "6A82FB", "FFD200", "38EF7D", "2C3E50"] : saved
    }

    var body: some View {
        let current = history.first
        Group {
            if model.family == .small {
                VStack(alignment: .leading, spacing: 6) {
                    swatch(current)
                    HStack(spacing: 4) {
                        hexLabel(current, size: 14)
                        Spacer(minLength: 0)
                        Button(action: pick) { Image(systemName: "eyedropper").font(.system(size: 13, weight: .semibold)) }
                            .buttonStyle(WidgetButtonStyle())
                            .help("Pick a colour from anywhere on screen")
                    }
                }
            } else {
                HStack(spacing: 14) {
                    swatch(current).aspectRatio(1, contentMode: .fit)
                    VStack(alignment: .leading, spacing: 3) {
                        hexLabel(current, size: 20)
                        if let current, let value = UInt32(current, radix: 16) {
                            let rgb = "rgb(\(value >> 16 & 255), \(value >> 8 & 255), \(value & 255))"
                            Text(rgb)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .fitLine(0.7)
                                .onTapGesture { copy(rgb) }
                        }
                        Spacer(minLength: 0)
                        if history.count > 1 {
                            HStack(spacing: 6) {
                                ForEach(history.dropFirst().prefix(6), id: \.self) { hex in
                                    Circle()
                                        .fill(Color(hex: UInt32(hex, radix: 16) ?? 0))
                                        .frame(width: 24, height: 24)
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15)))
                                        .onTapGesture { copy("#" + hex) }
                                        .help("#" + hex)
                                }
                            }
                        }
                        Button(action: pick) { Label("Pick a colour", systemImage: "eyedropper") }
                            .font(.system(size: 11.5, weight: .semibold))
                            .buttonStyle(WidgetButtonStyle())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { CopiedBadge(visible: copied) }
        .animation(.spring(duration: 0.25), value: copied)
        .widgetPadding()
    }

    /// The big colour chip; click it to pick a new colour.
    private func swatch(_ current: String?) -> some View {
        Button(action: pick) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(current.map { Color(hex: UInt32($0, radix: 16) ?? 0) } ?? Color.primary.opacity(0.1))
                if current == nil {
                    Image(systemName: "eyedropper").font(.system(size: 22, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
        }
        .buttonStyle(WidgetButtonStyle())
        .help("Pick a colour from anywhere on screen")
    }

    private func hexLabel(_ current: String?, size: CGFloat) -> some View {
        Text(current.map { "#" + $0 } ?? "Pick a colour")
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .fitLine(0.6)
            .onTapGesture { if let current { copy("#" + current) } }
    }

    private func pick() {
        guard context == .desktop else { return }
        NSColorSampler().show { color in
            guard let rgb = color?.usingColorSpace(.sRGB) else { return }
            let hex = String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
            model.config[ColorPickerKeys.history] = Array(([hex] + model[ColorPickerKeys.history].filter { $0 != hex }).prefix(12))
            copy("#" + hex)
        }
    }

    private func copy(_ text: String) {
        copyToClipboard(text)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
    }
}

// MARK: - Recent files & screenshots

/// Lists recently changed files in a few folders. Visibility-aware like every monitor.
final class RecentFilesMonitor: PollingMonitor {
    static let shared = RecentFilesMonitor()

    struct File: Identifiable, Equatable {
        var id: String { url.path }
        let url: URL
        let modified: Date
    }

    @Published private(set) var recent: [File] = []
    @Published private(set) var screenshots: [File] = []
    private let queue = DispatchQueue(label: "HomeWidgets.recentFiles", qos: .utility)

    override var interval: TimeInterval { 20 }

    static var screenshotFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let saved = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !saved.isEmpty {
            return URL(fileURLWithPath: (saved as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }

    override func sample() {
        queue.async { [weak self] in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let folders = ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0, isDirectory: true) }
            let recent = Array(folders.flatMap(Self.files(in:)).sorted { $0.modified > $1.modified }.prefix(12))
            let shots = Array(Self.files(in: Self.screenshotFolder)
                .filter { name in
                    let lower = name.url.lastPathComponent.lowercased()
                    let image = ["png", "jpg", "jpeg", "heic", "mov"].contains(name.url.pathExtension.lowercased())
                    return image && (lower.hasPrefix("screenshot") || lower.hasPrefix("screen shot") || lower.hasPrefix("cleanshot") || lower.hasPrefix("screen recording"))
                }
                .sorted { $0.modified > $1.modified }
                .prefix(12))
            DispatchQueue.main.async {
                guard let self else { return }
                if self.recent != recent { self.recent = recent }
                if self.screenshots != shots { self.screenshots = shots }
            }
        }
    }

    private static func files(in folder: URL) -> [File] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey, .isPackageKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
        return items.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true || values.isPackage == true,
                  let date = values.contentModificationDate else { return nil }
            return File(url: url, modified: date)
        }
    }
}

private struct FileTile: View {
    let file: RecentFilesMonitor.File
    var thumbnail = false

    var body: some View {
        Button { NSWorkspace.shared.open(file.url) } label: {
            VStack(spacing: 3) {
                Group {
                    if thumbnail, let image = ImageStore.image(at: file.url.path, maxPixel: 220) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path)).resizable().aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: thumbnail ? 64 : 38, height: thumbnail ? 44 : 38)
                .clipShape(RoundedRectangle(cornerRadius: thumbnail ? 6 : 0, style: .continuous))
                Text(file.url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(WidgetButtonStyle())
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
        .help("\(file.url.lastPathComponent) · \(Fmt.ago(file.modified)) — click to open, drag to use it somewhere")
    }
}

struct RecentFilesWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var monitor = RecentFilesMonitor.shared
    @Environment(\.widgetContext) private var context

    var body: some View {
        let limit = model.family == .small ? 4 : model.family == .medium ? 8 : 12
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Recent Files", symbol: "clock.arrow.circlepath", color: .blue)
            if monitor.recent.isEmpty {
                WidgetMessage(symbol: "doc", title: context == .gallery ? "Your latest files" : "Nothing recent",
                              detail: "Files you change in Desktop, Documents and Downloads show up here.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: model.family == .small ? 2 : 4), spacing: 8) {
                    ForEach(monitor.recent.prefix(limit)) { FileTile(file: $0) }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
        .monitoring(if: context == .desktop, monitor)
    }
}

struct ScreenshotsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var monitor = RecentFilesMonitor.shared
    @Environment(\.widgetContext) private var context

    var body: some View {
        let limit = model.family == .small ? 4 : model.family == .medium ? 8 : 12
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                WidgetHeader(title: "Screenshots", symbol: "camera.viewfinder", color: .purple)
                Button { _ = Shell.launch("/usr/bin/open", ["-a", "Screenshot"]) } label: {
                    Image(systemName: "plus.viewfinder").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(WidgetButtonStyle())
                .help("Take a screenshot")
            }
            if monitor.screenshots.isEmpty {
                WidgetMessage(symbol: "camera.viewfinder", title: "No screenshots yet",
                              detail: "Press ⌘⇧4 — new screenshots appear here, ready to drag into a message.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: model.family == .small ? 2 : 4), spacing: 8) {
                    ForEach(monitor.screenshots.prefix(limit)) { FileTile(file: $0, thumbnail: true) }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
        .monitoring(if: context == .desktop, monitor)
    }
}

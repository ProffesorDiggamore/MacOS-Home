import SwiftUI
import AppKit
import CoreLocation

// MARK: - Air quality

/// Air quality from Open-Meteo (free, no account), for your location or a city.
final class AirQualityService: ObservableObject {
    static let shared = AirQualityService()

    struct Report: Equatable {
        var place: String
        var aqi: Int
        var pm25: Double
        var pm10: Double
        var ozone: Double
        var uv: Double
        var updated: Date
    }

    @Published private(set) var reports: [String: Report] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var lastFetch: [String: Date] = [:]
    private let locator = Locator()

    func refresh(city: String, force: Bool = false) {
        let key = city.trimmingCharacters(in: .whitespaces)
        if !force, let last = lastFetch[key], Date().timeIntervalSince(last) < 1800 { return }
        lastFetch[key] = Date()
        if key.isEmpty {
            locator.request { [weak self] result in
                switch result {
                case .success(let location):
                    CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
                        let place = marks?.first.flatMap { $0.locality ?? $0.name } ?? "My Location"
                        self?.fetch(lat: location.coordinate.latitude, lon: location.coordinate.longitude, place: place, key: key)
                    }
                case .failure:
                    DispatchQueue.main.async { self?.errors[key] = "Allow Location, or type a city in Edit Widget." }
                }
            }
        } else {
            var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
            components?.queryItems = [URLQueryItem(name: "name", value: key.split(separator: ",").first.map(String.init) ?? key),
                                      URLQueryItem(name: "count", value: "1")]
            guard let url = components?.url else { return }
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let first = (object["results"] as? [[String: Any]])?.first,
                      let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
                    DispatchQueue.main.async { self?.errors[key] = "Couldn't find “\(key)”." }
                    return
                }
                self?.fetch(lat: lat, lon: lon, place: first["name"] as? String ?? key, key: key)
            }.resume()
        }
    }

    private func fetch(lat: Double, lon: Double, place: String, key: String) {
        let query = "latitude=\(String(format: "%.3f", lat))&longitude=\(String(format: "%.3f", lon))&current=us_aqi,pm2_5,pm10,ozone,uv_index&timezone=auto"
        guard let url = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality?" + query) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let current = object["current"] as? [String: Any] else {
                DispatchQueue.main.async { self?.errors[key] = "No internet connection." }
                return
            }
            func number(_ name: String) -> Double { (current[name] as? NSNumber)?.doubleValue ?? 0 }
            let report = Report(place: place, aqi: Int(number("us_aqi")), pm25: number("pm2_5"), pm10: number("pm10"),
                                ozone: number("ozone"), uv: number("uv_index"), updated: Date())
            DispatchQueue.main.async {
                self?.errors[key] = nil
                self?.reports[key] = report
            }
        }.resume()
    }

    static func level(_ aqi: Int) -> (String, Color) {
        switch aqi {
        case ..<51: return ("Good", .green)
        case ..<101: return ("Moderate", .yellow)
        case ..<151: return ("Unhealthy for some", .orange)
        case ..<201: return ("Unhealthy", .red)
        case ..<301: return ("Very unhealthy", .purple)
        default: return ("Hazardous", Color(hex: 0x7E0023))
        }
    }
}

enum AirKeys {
    static let city = ConfigKey("city", "")
}

struct AirQualityWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = AirQualityService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var key: String { model[AirKeys.city].trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let report = context == .gallery
            ? AirQualityService.Report(place: "Denver", aqi: 38, pm25: 6.2, pm10: 11, ozone: 61, uv: 4, updated: Date())
            : service.reports[key]
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Air Quality", symbol: "aqi.medium", color: .mint, trailing: report?.place)
            if let report {
                let (label, color) = AirQualityService.level(report.aqi)
                HStack(alignment: .center, spacing: 10) {
                    RingGauge(value: min(1, Double(report.aqi) / 300), color: color, lineWidth: 6) {
                        Text("\(report.aqi)").font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                    .frame(width: 62, height: 62)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(style.tone(color)).lineLimit(2)
                        Text("US AQI").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                if model.family != .small {
                    HStack(spacing: 12) {
                        stat("PM2.5", String(format: "%.0f", report.pm25))
                        stat("PM10", String(format: "%.0f", report.pm10))
                        stat("Ozone", String(format: "%.0f", report.ozone))
                        stat("UV", String(format: "%.0f", report.uv))
                    }
                }
            } else {
                Text(service.errors[key] ?? "Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
        .onAppear { if context == .desktop { service.refresh(city: key) } }
        .onChange(of: key) { _, value in service.refresh(city: value, force: true) }
        .onReceive(Timer.publish(every: 1800, tolerance: 120, on: .main, in: .common).autoconnect()) { _ in
            if context == .desktop { service.refresh(city: key) }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}

// MARK: - GitHub repo

final class RepoStatsService: ObservableObject {
    static let shared = RepoStatsService()

    struct Stats: Equatable {
        var name: String
        var description: String
        var stars: Int
        var forks: Int
        var issues: Int
        var release: String?
        var lastCommit: String?
        var pushed: Date?
    }

    @Published private(set) var stats: [String: Stats] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var lastFetch: [String: Date] = [:]

    /// Uses your GitHub token when you've connected one (needed for private repos), otherwise GitHub's public API.
    private func get(_ path: String, completion: @escaping (Any?, Int) -> Void) {
        if GitHubService.shared.currentToken != nil {
            GitHubService.shared.get(path, completion: completion)
            return
        }
        guard let url = URL(string: "https://api.github.com" + path) else { return completion(nil, 0) }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            DispatchQueue.main.async { completion(json, status) }
        }.resume()
    }

    func refresh(_ rawRepo: String, force: Bool = false) {
        let repo = CairnService.normalize(rawRepo)
        guard repo.contains("/") else { return }
        if !force, let last = lastFetch[repo], Date().timeIntervalSince(last) < 600 { return }
        lastFetch[repo] = Date()
        get("/repos/\(repo)") { [weak self] json, status in
            guard let self else { return }
            guard status == 200, let object = json as? [String: Any] else {
                self.errors[repo] = status == 404 ? "Repo not found (private repos need a GitHub token in Accounts)." : "Couldn't load \(repo)."
                return
            }
            var stats = Stats(name: object["name"] as? String ?? repo,
                              description: object["description"] as? String ?? "",
                              stars: object["stargazers_count"] as? Int ?? 0,
                              forks: object["forks_count"] as? Int ?? 0,
                              issues: object["open_issues_count"] as? Int ?? 0,
                              pushed: (object["pushed_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
            self.errors[repo] = nil
            self.stats[repo] = stats
            self.get("/repos/\(repo)/releases/latest") { json, status in
                if status == 200 { stats.release = (json as? [String: Any])?["tag_name"] as? String }
                self.get("/repos/\(repo)/commits?per_page=1") { json, _ in
                    let commit = ((json as? [[String: Any]])?.first?["commit"] as? [String: Any])?["message"] as? String
                    stats.lastCommit = commit?.split(separator: "\n").first.map(String.init)
                    self.stats[repo] = stats
                }
            }
        }
    }
}

enum RepoKeys {
    static let repo = ConfigKey("repo", "ProffesorDiggamore/MacOS-Home")
}

struct GitHubRepoWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var service = RepoStatsService.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var repo: String { CairnService.normalize(model[RepoKeys.repo]) }

    var body: some View {
        let stats = context == .gallery
            ? RepoStatsService.Stats(name: "MacOS-Home", description: "Apple-style widgets for your Mac desktop", stars: 128, forks: 14, issues: 3,
                                     release: "v3.0", lastCommit: "Grid layout and 30 new widgets", pushed: Date().addingTimeInterval(-3600))
            : service.stats[repo]
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: stats?.name ?? repo, symbol: "shippingbox.fill", color: .purple, trailing: stats?.release)
            if let stats {
                if model.family != .small && !stats.description.isEmpty {
                    Text(stats.description).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 12) {
                    count("star.fill", stats.stars, .yellow)
                    count("tuningfork", stats.forks, .blue)
                    count("smallcircle.filled.circle", stats.issues, .green)
                }
                Spacer(minLength: 0)
                if let commit = stats.lastCommit {
                    Text(commit).font(.system(size: 11, weight: .medium)).lineLimit(model.family == .small ? 2 : 1)
                }
                if let pushed = stats.pushed {
                    Text("Updated \(Fmt.ago(pushed))").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                Text(service.errors[repo] ?? "Loading…").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .widgetPadding()
        .contentShape(Rectangle())
        .onTapGesture { if let url = URL(string: "https://github.com/\(repo)") { NSWorkspace.shared.open(url) } }
        .onAppear { if context == .desktop { service.refresh(repo) } }
        .onChange(of: repo) { _, value in service.refresh(value, force: true) }
        .onReceive(Timer.publish(every: 900, tolerance: 60, on: .main, in: .common).autoconnect()) { _ in
            if context == .desktop { service.refresh(repo) }
        }
    }

    private func count(_ symbol: String, _ value: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(style.tone(color))
            Text(Fmt.count(value)).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}

// MARK: - Water

enum WaterKeys {
    static let count = ConfigKey("count", 0)
    static let day = ConfigKey("day", "")
    static let goal = ConfigKey("goal", 8)
}

struct WaterWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetIsVisible) private var visible

    private var today: String { DateFormats.string(Date(), format: "yyyy-MM-dd") }
    private var count: Int {
        if context == .gallery { return 5 }
        return model[WaterKeys.day] == today ? model[WaterKeys.count] : 0
    }

    var body: some View {
        let goal = max(1, model[WaterKeys.goal])
        let level = min(1, Double(count) / Double(goal))
        HStack(spacing: 12) {
            Animated(fps: visible ? 24 : 1) { date in
                WaterGlass(level: level, phase: date.timeIntervalSinceReferenceDate)
            }
            .frame(width: model.family == .small ? 54 : 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(count) of \(goal)").font(.system(size: 20, weight: .bold, design: .rounded))
                Text(count >= goal ? "Goal reached 💧" : "glasses today").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button { change(-1) } label: { Image(systemName: "minus.circle.fill") }
                    Button { change(1) } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.cyan) }
                }
                .font(.system(size: 22))
                .buttonStyle(WidgetButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    private func change(_ delta: Int) {
        guard context == .desktop else { return }
        model.config[WaterKeys.day] = today
        model.config[WaterKeys.count] = max(0, count + delta)
    }
}

private struct WaterGlass: View {
    let level: Double
    let phase: Double

    var body: some View {
        Canvas { context, size in
            let glass = Path { p in
                p.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.04))
                p.addLine(to: CGPoint(x: size.width * 0.88, y: size.height * 0.04))
                p.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.97))
                p.addLine(to: CGPoint(x: size.width * 0.22, y: size.height * 0.97))
                p.closeSubpath()
            }
            context.fill(glass, with: .color(.cyan.opacity(0.08)))
            var inside = context
            inside.clip(to: glass)
            let top = size.height * (0.97 - 0.93 * level)
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: size.height))
            for x in stride(from: 0.0, through: size.width, by: 2) {
                let y = top + sin(x / size.width * .pi * 2 + phase * 2.4) * 2.5
                wave.addLine(to: CGPoint(x: x, y: y))
            }
            wave.addLine(to: CGPoint(x: size.width, y: size.height))
            wave.closeSubpath()
            inside.fill(wave, with: .linearGradient(Gradient(colors: [Color(hex: 0x5AC8FA), Color(hex: 0x007AFF)]),
                                                    startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(glass, with: .color(.primary.opacity(0.35)), lineWidth: 1.5)
        }
    }
}

// MARK: - Quote of the day

enum QuoteBank {
    static let quotes: [(String, String)] = [
        ("The secret of getting ahead is getting started.", "Mark Twain"),
        ("It always seems impossible until it's done.", "Nelson Mandela"),
        ("Well done is better than well said.", "Benjamin Franklin"),
        ("Whatever you are, be a good one.", "Abraham Lincoln"),
        ("Simplicity is the ultimate sophistication.", "Leonardo da Vinci"),
        ("The best way out is always through.", "Robert Frost"),
        ("Do what you can, with what you have, where you are.", "Theodore Roosevelt"),
        ("Act as if what you do makes a difference. It does.", "William James"),
        ("Quality is not an act, it is a habit.", "Aristotle"),
        ("Stay hungry, stay foolish.", "Stewart Brand"),
        ("Make it work, make it right, make it fast.", "Kent Beck"),
        ("Talk is cheap. Show me the code.", "Linus Torvalds"),
        ("The only way to do great work is to love what you do.", "Steve Jobs"),
        ("Courage is grace under pressure.", "Ernest Hemingway"),
        ("Knowing is not enough; we must apply.", "Johann Wolfgang von Goethe"),
        ("What we think, we become.", "Buddha"),
        ("Fall seven times, stand up eight.", "Japanese proverb"),
        ("A smooth sea never made a skilled sailor.", "Franklin D. Roosevelt"),
        ("If you can dream it, you can do it.", "Walt Disney"),
        ("Small deeds done are better than great deeds planned.", "Peter Marshall"),
        ("The harder I work, the luckier I get.", "Samuel Goldwyn"),
        ("Energy and persistence conquer all things.", "Benjamin Franklin"),
        ("Every moment is a fresh beginning.", "T. S. Eliot"),
        ("Be so good they can't ignore you.", "Steve Martin"),
        ("Done is better than perfect.", "Sheryl Sandberg"),
        ("Start where you are. Use what you have. Do what you can.", "Arthur Ashe"),
        ("Believe you can and you're halfway there.", "Theodore Roosevelt"),
        ("Dream big and dare to fail.", "Norman Vaughan"),
        ("The future depends on what you do today.", "Mahatma Gandhi"),
        ("Hard work beats talent when talent doesn't work hard.", "Tim Notke"),
    ]
}

struct QuoteWidget: View {
    @ObservedObject var model: WidgetModel
    @State private var offset = 0

    var body: some View {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let quote = QuoteBank.quotes[((day + offset) % QuoteBank.quotes.count + QuoteBank.quotes.count) % QuoteBank.quotes.count]
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "quote.opening").font(.system(size: 16, weight: .bold)).foregroundStyle(.secondary)
            Text(quote.0)
                .font(.system(size: model.family == .small ? 14 : 17, weight: .medium, design: .serif))
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
            HStack {
                Text("— " + quote.1).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { offset += 1 } label: { Image(systemName: "arrow.right.circle") }
                    .buttonStyle(WidgetButtonStyle())
                    .foregroundStyle(.secondary)
            }
        }
        .widgetPadding(16)
    }
}

// MARK: - Breathe

enum BreatheKeys {
    static let pattern = ConfigKey("pattern", BreathePattern.box)
}

enum BreathePattern: String, ConfigOption {
    case box, calm, energize
    var label: String {
        switch self {
        case .box: return "Box (4-4-4-4)"
        case .calm: return "Calm (4-7-8)"
        case .energize: return "Energize (4-0-4-0)"
        }
    }
    /// Seconds: in, hold, out, hold.
    var steps: [Double] {
        switch self {
        case .box: return [4, 4, 4, 4]
        case .calm: return [4, 7, 8, 0]
        case .energize: return [4, 0, 4, 0]
        }
    }
}

struct BreatheWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @State private var started: Date?

    var body: some View {
        let steps = model[BreatheKeys.pattern].steps
        let cycle = steps.reduce(0, +)
        Animated(fps: started == nil && context != .gallery ? 1 : 30) { date in
            let running = started != nil || context == .gallery
            let t = running ? date.timeIntervalSince(started ?? Date(timeIntervalSinceReferenceDate: 0)).truncatingRemainder(dividingBy: cycle) : 0
            let (label, scale) = Self.state(t: t, steps: steps, running: running)
            ZStack {
                ForEach(0..<6) { index in
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0x6EE7F9).opacity(0.55), Color(hex: 0x8B5CF6).opacity(0.45)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                        .offset(x: 18 * scale)
                        .rotationEffect(.degrees(Double(index) * 60 + t * 6))
                        .blendMode(.plusLighter)
                }
                .scaleEffect(0.55 + 0.6 * scale)
                VStack {
                    Spacer()
                    Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .onTapGesture { started = started == nil ? Date() : nil }
        .widgetPadding(10)
        .widgetBackground(.gradient(Color(hex: 0x111827), Color(hex: 0x1E1B4B)))
        .environment(\.colorScheme, .dark)
        .help("Click to start or stop")
    }

    /// Where in the breath we are: label and how open the flower is (0…1).
    static func state(t: Double, steps: [Double], running: Bool) -> (String, Double) {
        guard running else { return ("Tap to breathe", 0.35) }
        var time = t
        let labels = ["Breathe in", "Hold", "Breathe out", "Hold"]
        for (index, length) in steps.enumerated() where length > 0 {
            if time < length {
                let progress = time / length
                let eased = 0.5 - cos(progress * .pi) / 2
                switch index {
                case 0: return (labels[0], eased)
                case 1: return (labels[1], 1)
                case 2: return (labels[2], 1 - eased)
                default: return (labels[3], 0)
                }
            }
            time -= length
        }
        return (labels[0], 0)
    }
}

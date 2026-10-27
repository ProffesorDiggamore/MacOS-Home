import SwiftUI
import AppKit

/// Asks a remote resource for fresh data when shown and every `every` seconds after that.
private struct RemoteRefresher<Value: Equatable>: ViewModifier {
    let resource: RemoteResource<Value>
    let key: String
    let every: TimeInterval
    let enabled: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { if enabled { resource.request(key) } }
            .onChange(of: key) { _, newKey in if enabled { resource.request(newKey) } }
            .onReceive(Timer.publish(every: every, tolerance: every * 0.1, on: .main, in: .common).autoconnect()) { _ in
                if enabled { resource.request(key) }
            }
    }
}

private extension View {
    func refreshing<Value: Equatable>(_ resource: RemoteResource<Value>, key: String, every: TimeInterval, enabled: Bool = true) -> some View {
        modifier(RemoteRefresher(resource: resource, key: key, every: every, enabled: enabled))
    }
}

private struct LoadingOrError: View {
    let error: String?
    var body: some View {
        if let error {
            WidgetMessage(symbol: "wifi.exclamationmark", title: "Couldn't load", detail: error)
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Stocks & crypto

enum QuoteKeys {
    static let stocks = ConfigKey<[String]>("symbols", ["AAPL", "NVDA", "MSFT", "TSLA", "GOOGL"])
    static let crypto = ConfigKey<[String]>("symbols", ["BTC-USD", "ETH-USD", "SOL-USD", "DOGE-USD"])
}

struct QuotesWidget: View {
    @ObservedObject var model: WidgetModel
    let isCrypto: Bool
    @ObservedObject private var remote = Remote.quotes

    private var symbols: [String] { model[isCrypto ? QuoteKeys.crypto : QuoteKeys.stocks] }
    private var key: String { symbols.joined(separator: ",") }

    var body: some View {
        Group {
            if let quotes = remote.values[key], !quotes.isEmpty {
                switch model.family {
                case .small:
                    if let first = quotes.first { single(first) }
                case .medium: list(quotes, limit: 3)
                case .large: list(quotes, limit: 7)
                }
            } else {
                LoadingOrError(error: remote.errors[key])
            }
        }
        .refreshing(remote, key: key, every: 300)
    }

    private func label(_ quote: Quote) -> String {
        isCrypto ? quote.symbol.replacingOccurrences(of: "-USD", with: "") : quote.symbol
    }

    private func price(_ value: Double) -> String {
        if value >= 1000 { return value.formatted(.number.precision(.fractionLength(0))) }
        if value >= 1 { return String(format: "%.2f", value) }
        return String(format: "%.4f", value)
    }

    private func change(_ quote: Quote) -> some View {
        Text(String(format: "%@%.2f%%", quote.change >= 0 ? "+" : "", quote.changePercent))
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(quote.change >= 0 ? Color.green : Color.red))
    }

    private func chart(_ quote: Quote) -> some View {
        let low = min(quote.points.min() ?? quote.price, quote.previousClose)
        let high = max(quote.points.max() ?? quote.price, quote.previousClose)
        let span = max(high - low, 0.000_001)
        return Sparkline(values: quote.points.map { ($0 - low) / span }, color: quote.change >= 0 ? .green : .red,
                         capacity: max(quote.points.count, 26))
    }

    private func single(_ quote: Quote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label(quote)).font(.system(size: 15, weight: .bold))
                Spacer()
                change(quote)
            }
            Text(quote.name).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            chart(quote).frame(maxHeight: .infinity)
            Text(price(quote.price))
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .widgetPadding()
    }

    private func list(_ quotes: [Quote], limit: Int) -> some View {
        VStack(spacing: 6) {
            ForEach(quotes.prefix(limit)) { quote in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(label(quote)).font(.system(size: 13, weight: .bold))
                        Text(quote.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 92, alignment: .leading)
                    chart(quote).frame(height: 26)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(price(quote.price)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                        change(quote)
                    }
                    .frame(width: 78, alignment: .trailing)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .widgetPadding()
    }
}

// MARK: - Currency

enum CurrencyKeys {
    static let base = ConfigKey("base", "USD")
    static let targets = ConfigKey<[String]>("targets", ["EUR", "GBP", "JPY", "MXN", "CAD"])
    static let amount = ConfigKey("amount", 1.0)
}

struct CurrencyWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var remote = Remote.rates

    private var key: String { model[CurrencyKeys.base].uppercased() + "|" + model[CurrencyKeys.targets].map { $0.uppercased() }.joined(separator: ",") }

    private func flag(_ code: String) -> String {
        let region = String(code.prefix(2))
        if code == "EUR" { return "🇪🇺" }
        let scalars = region.unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }
        return scalars.map { String(Character($0)) }.joined()
    }

    var body: some View {
        let amount = model[CurrencyKeys.amount]
        Group {
            if let rates = remote.values[key] {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(flag(rates.base)) \(String(format: "%g", amount)) \(rates.base)")
                            .font(.system(size: 13, weight: .bold))
                        Spacer()
                        Text(rates.date).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(rates.rates.prefix(model.family == .small ? 4 : 6).enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text("\(flag(entry.0)) \(entry.0)").font(.system(size: 12.5, weight: .medium))
                            Spacer()
                            Text(String(format: entry.1 * amount >= 100 ? "%.0f" : "%.2f", entry.1 * amount))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding()
            } else {
                LoadingOrError(error: remote.errors[key])
            }
        }
        .refreshing(remote, key: key, every: 3600)
    }
}

// MARK: - Sports

enum SportsKeys {
    static let league = ConfigKey("league", League.nfl)
    static let team = ConfigKey("team", "")
}

enum League: String, ConfigOption {
    case nfl, nba, mlb, nhl, collegeFootball, collegeBasketball, premierLeague, mls, wnba

    var label: String {
        switch self {
        case .nfl: return "NFL"
        case .nba: return "NBA"
        case .mlb: return "MLB"
        case .nhl: return "NHL"
        case .collegeFootball: return "College Football"
        case .collegeBasketball: return "College Basketball"
        case .premierLeague: return "Premier League"
        case .mls: return "MLS"
        case .wnba: return "WNBA"
        }
    }

    var path: String {
        switch self {
        case .nfl: return "football/nfl"
        case .nba: return "basketball/nba"
        case .mlb: return "baseball/mlb"
        case .nhl: return "hockey/nhl"
        case .collegeFootball: return "football/college-football"
        case .collegeBasketball: return "basketball/mens-college-basketball"
        case .premierLeague: return "soccer/eng.1"
        case .mls: return "soccer/usa.1"
        case .wnba: return "basketball/wnba"
        }
    }

    var symbol: String {
        switch self {
        case .nfl, .collegeFootball: return "football.fill"
        case .nba, .collegeBasketball, .wnba: return "basketball.fill"
        case .mlb: return "baseball.fill"
        case .nhl: return "hockey.puck.fill"
        case .premierLeague, .mls: return "soccerball"
        }
    }
}

struct SportsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var remote = Remote.scores

    private var league: League { model[SportsKeys.league] }

    private var games: [Game] {
        let all = remote.values[league.path] ?? []
        let team = model[SportsKeys.team].uppercased()
        let filtered = team.isEmpty ? all : all.filter { $0.home.abbreviation == team || $0.away.abbreviation == team }
        // Live games first, then upcoming, then finished.
        let order = ["in": 0, "pre": 1, "post": 2]
        return filtered.sorted { (order[$0.state] ?? 3, $0.date ?? .distantFuture) < (order[$1.state] ?? 3, $1.date ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if remote.values[league.path] != nil {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: league.symbol).foregroundStyle(Color.orange)
                        Text(league.label).font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        if games.contains(where: { $0.state == "in" }) {
                            Text("LIVE").font(.system(size: 9.5, weight: .heavy))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule().fill(Color.red))
                        }
                    }
                    if games.isEmpty {
                        Spacer(minLength: 0)
                        Text("No games scheduled right now").font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    } else {
                        ForEach(games.prefix(model.family == .large ? 6 : 2)) { game in
                            GameRow(game: game)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding()
            } else {
                LoadingOrError(error: remote.errors[league.path])
            }
        }
        .refreshing(remote, key: league.path, every: 120)
    }
}

private struct GameRow: View {
    let game: Game

    private func teamLine(_ team: Game.Team) -> some View {
        HStack(spacing: 6) {
            AsyncImage(url: team.logo) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Circle().fill(Color(hex: UInt32(team.color ?? "888888", radix: 16) ?? 0x888888))
            }
            .frame(width: 18, height: 18)
            Text(team.abbreviation)
                .font(.system(size: 12.5, weight: team.isWinner ? .bold : .medium))
            Spacer(minLength: 4)
            if game.state != "pre" {
                Text(team.score)
                    .font(.system(size: 14, weight: team.isWinner || game.state == "in" ? .bold : .regular, design: .rounded))
                    .monospacedDigit()
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 3) {
                teamLine(game.away)
                teamLine(game.home)
            }
            Text(game.detail)
                .font(.system(size: 10, weight: game.state == "in" ? .bold : .medium))
                .foregroundStyle(game.state == "in" ? Color.red : Color.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(width: 86, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - News feed

enum NewsKeys {
    static let feed = ConfigKey("feed", "https://www.apple.com/newsroom/rss-feed.rss")
}

struct NewsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var remote = Remote.feeds

    private var feedURL: String { model[NewsKeys.feed].trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Group {
            if let feed = remote.values[feedURL] {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "newspaper.fill").foregroundStyle(Color.red)
                        Text(feed.title.isEmpty ? "News" : feed.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    ForEach(feed.items.prefix(model.family == .large ? 8 : 3)) { item in
                        Button {
                            if let url = URL(string: item.link) { NSWorkspace.shared.open(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                if let date = item.date {
                                    Text(Fmt.ago(date)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(WidgetButtonStyle())
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding()
            } else {
                LoadingOrError(error: remote.errors[feedURL])
            }
        }
        .refreshing(remote, key: feedURL, every: 900)
    }
}

// MARK: - Hacker News

struct HackerNewsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var remote = Remote.hackerNews

    var body: some View {
        Group {
            if let stories = remote.values["top"] {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("Y")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 18, height: 18)
                            .background(Rectangle().fill(Color(hex: 0xFF6600)))
                        Text("Hacker News").font(.system(size: 12.5, weight: .semibold))
                    }
                    ForEach(Array(stories.prefix(model.family == .large ? 9 : 3).enumerated()), id: \.element.id) { index, story in
                        Button {
                            let link = story.url ?? "https://news.ycombinator.com/item?id=\(story.id)"
                            if let url = URL(string: link) { NSWorkspace.shared.open(url) }
                        } label: {
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(story.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                    Text("\(story.score) points · \(story.comments) comments")
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(WidgetButtonStyle())
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding()
            } else {
                LoadingOrError(error: remote.errors["top"])
            }
        }
        .refreshing(remote, key: "top", every: 600)
    }
}

// MARK: - Website monitor

enum UptimeKeys {
    static let sites = ConfigKey<[String]>("sites", ["apple.com", "github.com", "claude.ai"])
}

struct UptimeWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var remote = Remote.sites

    private var key: String { model[UptimeKeys.sites].joined(separator: "\n") }

    var body: some View {
        Group {
            if let sites = remote.values[key] {
                let down = sites.filter { !$0.isUp }.count
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: down == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(down == 0 ? Color.green : Color.red)
                        Text(down == 0 ? "All sites up" : "\(down) down")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    ForEach(sites.prefix(model.family == .large ? 10 : (model.family == .medium ? 4 : 4))) { site in
                        HStack(spacing: 6) {
                            Circle().fill(site.isUp ? Color.green : Color.red).frame(width: 8, height: 8)
                            Text(site.url).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(site.isUp ? "\(site.milliseconds) ms" : (site.code == 0 ? "offline" : "\(site.code)"))
                                .font(.system(size: 10.5, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(site.isUp ? Color.secondary : Color.red)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding()
            } else {
                LoadingOrError(error: remote.errors[key])
            }
        }
        .refreshing(remote, key: key, every: 60)
    }
}

// MARK: - Service status

enum ServiceStatusKeys {
    static let services = ConfigKey<[String]>("services", ["claude", "github", "discord"])
}

struct ServiceStatusWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var remote = Remote.statuses

    private var key: String { model[ServiceStatusKeys.services].joined(separator: ",") }

    private func color(_ indicator: String) -> Color {
        switch indicator {
        case "none": return .green
        case "minor", "maintenance": return .yellow
        case "major": return .orange
        case "critical": return .red
        default: return .gray
        }
    }

    var body: some View {
        Group {
            if let states = remote.values[key] {
                let healthy = states.allSatisfy { $0.indicator == "none" }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: healthy ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(healthy ? Color.green : Color.orange)
                        Text(healthy ? "All systems go" : "Some issues")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    ForEach(states) { state in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().fill(color(state.indicator)).frame(width: 9, height: 9).padding(.top, 3)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(state.name).font(.system(size: 12.5, weight: .semibold))
                                if model.family != .small || state.indicator != "none" {
                                    Text(state.summary).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding()
            } else {
                LoadingOrError(error: remote.errors[key])
            }
        }
        .refreshing(remote, key: key, every: 300)
    }
}

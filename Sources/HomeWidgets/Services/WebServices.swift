import Foundation
import Combine

enum HTTP {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func data(_ url: URL, headers: [String: String] = [:], method: String = "GET", timeout: TimeInterval = 20,
                     completion: @escaping (Result<(Data, Int), Error>) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Mozilla/5.0 (Macintosh) HomeWidgets", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { return completion(.failure(error)) }
            completion(.success((data ?? Data(), (response as? HTTPURLResponse)?.statusCode ?? 0)))
        }.resume()
    }

    static func json(_ url: URL, completion: @escaping (Result<Any, Error>) -> Void) {
        data(url) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let (data, status)):
                guard status == 200, let object = try? JSONSerialization.jsonObject(with: data) else {
                    return completion(.failure(Failure(message: "Server returned \(status)")))
                }
                completion(.success(object))
            }
        }
    }
}

/// Caches network results per key (e.g. a list of stock symbols) and refetches when stale.
final class RemoteResource<Value: Equatable>: ObservableObject {
    @Published private(set) var values: [String: Value] = [:]
    @Published private(set) var errors: [String: String] = [:]
    private var lastFetch: [String: Date] = [:]
    private var inFlight = Set<String>()
    private let maxAge: TimeInterval
    private let fetcher: (String, @escaping (Result<Value, Error>) -> Void) -> Void

    init(maxAge: TimeInterval, fetcher: @escaping (String, @escaping (Result<Value, Error>) -> Void) -> Void) {
        self.maxAge = maxAge
        self.fetcher = fetcher
    }

    func request(_ key: String, force: Bool = false) {
        guard !key.isEmpty, !inFlight.contains(key) else { return }
        if !force, let last = lastFetch[key], Date().timeIntervalSince(last) < maxAge { return }
        inFlight.insert(key)
        lastFetch[key] = Date()
        fetcher(key) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(key)
                switch result {
                case .success(let value):
                    self.values[key] = value
                    self.errors[key] = nil
                case .failure(let error):
                    self.errors[key] = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Models

struct Quote: Identifiable, Equatable {
    var id: String { symbol }
    let symbol: String
    let name: String
    let price: Double
    let previousClose: Double
    let currency: String
    let points: [Double]

    var change: Double { price - previousClose }
    var changePercent: Double { previousClose != 0 ? change / previousClose * 100 : 0 }
}

struct ExchangeRates: Equatable {
    let base: String
    let date: String
    let rates: [(String, Double)]

    static func == (lhs: ExchangeRates, rhs: ExchangeRates) -> Bool {
        lhs.base == rhs.base && lhs.date == rhs.date && lhs.rates.map(\.0) == rhs.rates.map(\.0) && lhs.rates.map(\.1) == rhs.rates.map(\.1)
    }
}

struct Game: Identifiable, Equatable {
    struct Team: Equatable {
        let abbreviation: String
        let name: String
        let score: String
        let logo: URL?
        let color: String?
        let isWinner: Bool
    }
    let id: String
    let home: Team
    let away: Team
    let state: String // pre, in, post
    let detail: String
    let date: Date?
}

struct FeedItem: Identifiable, Equatable {
    var id: String { link.isEmpty ? title : link }
    let title: String
    let link: String
    let date: Date?
}

struct Feed: Equatable {
    let title: String
    let items: [FeedItem]
}

struct HNStory: Identifiable, Equatable {
    let id: Int
    let title: String
    let url: String?
    let score: Int
    let comments: Int
    let by: String
}

struct SiteStatus: Identifiable, Equatable {
    var id: String { url }
    let url: String
    let isUp: Bool
    let code: Int
    let milliseconds: Int
}

struct ServiceState: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let indicator: String // none, minor, major, critical, maintenance, unknown
    let summary: String
}

// MARK: - Shared resources

enum Remote {
    /// Stock and crypto prices with today's intraday chart (Yahoo Finance chart API, no key).
    static let quotes = RemoteResource<[Quote]>(maxAge: 240) { key, completion in
        let symbols = key.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.filter { !$0.isEmpty }
        let group = DispatchGroup()
        let lock = NSLock()
        var found: [String: Quote] = [:]
        for symbol in symbols {
            guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?range=1d&interval=15m") else { continue }
            group.enter()
            HTTP.json(url) { result in
                defer { group.leave() }
                guard case .success(let object) = result,
                      let chart = (object as? [String: Any])?["chart"] as? [String: Any],
                      let first = (chart["result"] as? [[String: Any]])?.first,
                      let meta = first["meta"] as? [String: Any],
                      let price = (meta["regularMarketPrice"] as? NSNumber)?.doubleValue else { return }
                let previous = (meta["chartPreviousClose"] as? NSNumber)?.doubleValue
                    ?? (meta["previousClose"] as? NSNumber)?.doubleValue ?? price
                let indicators = (first["indicators"] as? [String: Any])?["quote"] as? [[String: Any]]
                let closes = (indicators?.first?["close"] as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
                let name = (meta["shortName"] as? String) ?? (meta["longName"] as? String) ?? symbol
                let quote = Quote(symbol: symbol, name: name, price: price, previousClose: previous,
                                  currency: meta["currency"] as? String ?? "USD", points: closes)
                lock.lock()
                found[symbol] = quote
                lock.unlock()
            }
        }
        group.notify(queue: .global()) {
            let ordered = symbols.compactMap { found[$0] }
            if ordered.isEmpty && !symbols.isEmpty {
                completion(.failure(HTTP.Failure(message: "Couldn't load prices")))
            } else {
                completion(.success(ordered))
            }
        }
    }

    /// Currency exchange rates (frankfurter.app, European Central Bank data).
    static let rates = RemoteResource<ExchangeRates>(maxAge: 3600) { key, completion in
        let parts = key.split(separator: "|").map(String.init)
        guard parts.count == 2,
              let url = URL(string: "https://api.frankfurter.app/latest?from=\(parts[0])&to=\(parts[1])") else {
            return completion(.failure(HTTP.Failure(message: "Bad currencies")))
        }
        HTTP.json(url) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let object):
                guard let root = object as? [String: Any], let rates = root["rates"] as? [String: Any] else {
                    return completion(.failure(HTTP.Failure(message: "Unexpected response")))
                }
                let order = parts[1].split(separator: ",").map(String.init)
                let list = order.compactMap { code in (rates[code] as? NSNumber).map { (code, $0.doubleValue) } }
                completion(.success(ExchangeRates(base: parts[0], date: root["date"] as? String ?? "", rates: list)))
            }
        }
    }

    /// Scoreboards from ESPN's public API. Key is like "basketball/nba".
    static let scores = RemoteResource<[Game]>(maxAge: 90) { key, completion in
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(key)/scoreboard") else {
            return completion(.failure(HTTP.Failure(message: "Bad league")))
        }
        let iso = ISO8601DateFormatter()
        let isoShort = DateFormatter()
        isoShort.locale = Locale(identifier: "en_US_POSIX")
        isoShort.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        isoShort.timeZone = TimeZone(identifier: "UTC")
        HTTP.json(url) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let object):
                let events = (object as? [String: Any])?["events"] as? [[String: Any]] ?? []
                let games: [Game] = events.compactMap { event in
                    guard let competition = (event["competitions"] as? [[String: Any]])?.first,
                          let competitors = competition["competitors"] as? [[String: Any]] else { return nil }
                    func team(_ side: String) -> Game.Team? {
                        guard let entry = competitors.first(where: { ($0["homeAway"] as? String) == side }),
                              let info = entry["team"] as? [String: Any] else { return nil }
                        return Game.Team(abbreviation: info["abbreviation"] as? String ?? "?",
                                         name: info["shortDisplayName"] as? String ?? info["name"] as? String ?? "",
                                         score: entry["score"] as? String ?? "",
                                         logo: (info["logo"] as? String).flatMap(URL.init(string:)),
                                         color: info["color"] as? String,
                                         isWinner: entry["winner"] as? Bool ?? false)
                    }
                    guard let home = team("home"), let away = team("away") else { return nil }
                    let status = (event["status"] as? [String: Any])?["type"] as? [String: Any]
                    let stamp = event["date"] as? String ?? ""
                    return Game(id: event["id"] as? String ?? UUID().uuidString,
                                home: home, away: away,
                                state: status?["state"] as? String ?? "pre",
                                detail: status?["shortDetail"] as? String ?? "",
                                date: iso.date(from: stamp) ?? isoShort.date(from: stamp))
                }
                completion(.success(games))
            }
        }
    }

    /// Any RSS or Atom feed.
    static let feeds = RemoteResource<Feed>(maxAge: 900) { key, completion in
        guard let url = URL(string: key) else { return completion(.failure(HTTP.Failure(message: "Bad feed URL"))) }
        HTTP.data(url) { result in
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success(let (data, status)):
                guard status == 200 else { return completion(.failure(HTTP.Failure(message: "Feed returned \(status)"))) }
                let parser = FeedParser(data: data)
                if let feed = parser.parse() {
                    completion(.success(feed))
                } else {
                    completion(.failure(HTTP.Failure(message: "That doesn't look like an RSS feed")))
                }
            }
        }
    }

    /// Hacker News top stories.
    static let hackerNews = RemoteResource<[HNStory]>(maxAge: 600) { key, completion in
        guard let url = URL(string: "https://hacker-news.firebaseio.com/v0/\(key)stories.json") else {
            return completion(.failure(HTTP.Failure(message: "Bad list")))
        }
        HTTP.json(url) { result in
            guard case .success(let object) = result, let ids = object as? [Int] else {
                return completion(.failure(HTTP.Failure(message: "Couldn't load stories")))
            }
            let wanted = Array(ids.prefix(12))
            let group = DispatchGroup()
            let lock = NSLock()
            var stories: [Int: HNStory] = [:]
            for id in wanted {
                guard let itemURL = URL(string: "https://hacker-news.firebaseio.com/v0/item/\(id).json") else { continue }
                group.enter()
                HTTP.json(itemURL) { itemResult in
                    defer { group.leave() }
                    guard case .success(let item) = itemResult, let story = item as? [String: Any] else { return }
                    let entry = HNStory(id: id, title: story["title"] as? String ?? "",
                                        url: story["url"] as? String,
                                        score: story["score"] as? Int ?? 0,
                                        comments: story["descendants"] as? Int ?? 0,
                                        by: story["by"] as? String ?? "")
                    lock.lock()
                    stories[id] = entry
                    lock.unlock()
                }
            }
            group.notify(queue: .global()) {
                completion(.success(wanted.compactMap { stories[$0] }))
            }
        }
    }

    /// Checks websites with a quick request. Key is newline-separated URLs.
    static let sites = RemoteResource<[SiteStatus]>(maxAge: 55) { key, completion in
        let urls = key.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [String: SiteStatus] = [:]
        for raw in urls {
            let address = raw.contains("://") ? raw : "https://" + raw
            guard let url = URL(string: address) else { continue }
            group.enter()
            let start = Date()
            HTTP.data(url, method: "HEAD", timeout: 10) { result in
                defer { group.leave() }
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                var status = SiteStatus(url: raw, isUp: false, code: 0, milliseconds: elapsed)
                if case .success(let (_, code)) = result {
                    status = SiteStatus(url: raw, isUp: (200..<400).contains(code) || code == 405, code: code, milliseconds: elapsed)
                }
                lock.lock()
                results[raw] = status
                lock.unlock()
            }
        }
        group.notify(queue: .global()) {
            completion(.success(urls.compactMap { results[$0] }))
        }
    }

    /// Atlassian Statuspage summaries (Claude, GitHub, Discord, …).
    static let statuses = RemoteResource<[ServiceState]>(maxAge: 240) { key, completion in
        let services = key.split(separator: ",").map(String.init)
        let group = DispatchGroup()
        let lock = NSLock()
        var results: [String: ServiceState] = [:]
        for service in services {
            guard let page = StatusPage.all.first(where: { $0.id == service }),
                  let url = URL(string: page.base + "/api/v2/status.json") else { continue }
            group.enter()
            HTTP.json(url) { result in
                defer { group.leave() }
                var state = ServiceState(name: page.name, indicator: "unknown", summary: "Unavailable")
                if case .success(let object) = result,
                   let status = (object as? [String: Any])?["status"] as? [String: Any] {
                    state = ServiceState(name: page.name,
                                         indicator: status["indicator"] as? String ?? "unknown",
                                         summary: status["description"] as? String ?? "")
                }
                lock.lock()
                results[service] = state
                lock.unlock()
            }
        }
        group.notify(queue: .global()) {
            completion(.success(services.compactMap { results[$0] }))
        }
    }
}

struct StatusPage: Identifiable {
    let id: String
    let name: String
    let base: String

    static let all: [StatusPage] = [
        StatusPage(id: "claude", name: "Claude", base: "https://status.claude.com"),
        StatusPage(id: "github", name: "GitHub", base: "https://www.githubstatus.com"),
        StatusPage(id: "discord", name: "Discord", base: "https://discordstatus.com"),
        StatusPage(id: "openai", name: "OpenAI", base: "https://status.openai.com"),
        StatusPage(id: "cloudflare", name: "Cloudflare", base: "https://www.cloudflarestatus.com"),
        StatusPage(id: "vercel", name: "Vercel", base: "https://www.vercel-status.com"),
        StatusPage(id: "reddit", name: "Reddit", base: "https://www.redditstatus.com"),
        StatusPage(id: "notion", name: "Notion", base: "https://www.notion-status.com"),
    ]
}

/// Minimal RSS 2.0 / Atom parser.
final class FeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var feedTitle = ""
    private var items: [FeedItem] = []
    private var inItem = false
    private var element = ""
    private var title = ""
    private var link = ""
    private var dateText = ""

    init(data: Data) {
        self.data = data
    }

    func parse() -> Feed? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() || !items.isEmpty else { return nil }
        return items.isEmpty && feedTitle.isEmpty ? nil : Feed(title: feedTitle.trimmingCharacters(in: .whitespacesAndNewlines), items: items)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        element = elementName
        if elementName == "item" || elementName == "entry" {
            inItem = true
            title = ""
            link = ""
            dateText = ""
        }
        if inItem, elementName == "link", let href = attributeDict["href"], link.isEmpty,
           attributeDict["rel"] == nil || attributeDict["rel"] == "alternate" {
            link = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        append(String(data: CDATABlock, encoding: .utf8) ?? "")
    }

    private func append(_ text: String) {
        if inItem {
            switch element {
            case "title": title += text
            case "link": link += text
            case "pubDate", "updated", "published", "dc:date": dateText += text
            default: break
            }
        } else if element == "title" && feedTitle.isEmpty {
            feedTitle += text
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" || elementName == "entry" {
            inItem = false
            items.append(FeedItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                  link: link.trimmingCharacters(in: .whitespacesAndNewlines),
                                  date: Self.date(dateText.trimmingCharacters(in: .whitespacesAndNewlines))))
        } else if elementName == "title" && !inItem && !feedTitle.isEmpty {
            element = ""
        }
    }

    private static func date(_ text: String) -> Date? {
        if text.isEmpty { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        let rfc = DateFormatter()
        rfc.locale = Locale(identifier: "en_US_POSIX")
        for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z"] {
            rfc.dateFormat = format
            if let date = rfc.date(from: text) { return date }
        }
        return nil
    }
}

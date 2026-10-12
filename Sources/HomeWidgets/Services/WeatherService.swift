import Foundation
import CoreLocation
import Combine
import AppKit

struct WeatherReport: Equatable {
    struct Hour: Identifiable, Equatable {
        let id: Double
        let date: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
    }

    struct Day: Identifiable, Equatable {
        let id: Double
        let date: Date
        let code: Int
        let high: Double
        let low: Double
        let precipitation: Int?
    }

    var place: String
    var temperature: Double
    var apparent: Double
    var code: Int
    var isDay: Bool
    var humidity: Int?
    var wind: Double?
    var high: Double
    var low: Double
    var sunrise: Date?
    var sunset: Date?
    var hours: [Hour]
    var days: [Day]
    var fetched: Date

    /// Placeholder shown in the widget gallery.
    static var sample: WeatherReport {
        let now = Date()
        let hours = (0..<12).map { index in
            Hour(id: Double(index), date: now.addingTimeInterval(Double(index) * 3600),
                 temperature: 22 - Double(index) * 0.6, code: index < 4 ? 1 : 2, isDay: index < 6)
        }
        let codes = [1, 2, 3, 61, 0, 2, 1]
        let days = (0..<7).map { index in
            Day(id: Double(index), date: now.addingTimeInterval(Double(index) * 86400), code: codes[index],
                high: 24 - Double(index % 3), low: 14 + Double(index % 2), precipitation: index == 3 ? 70 : 10)
        }
        return WeatherReport(place: "Cupertino", temperature: 22, apparent: 21, code: 1, isDay: true, humidity: 48,
                             wind: 9, high: 24, low: 14, sunrise: nil, sunset: nil, hours: hours, days: days, fetched: now)
    }
}

/// WMO weather codes → SF Symbols and descriptions.
enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81: return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80, 81: return "Showers"
        case 82: return "Heavy Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorms"
        case 96, 99: return "Hail Storms"
        default: return "—"
        }
    }

    enum Sky { case clear, cloudy, rain, snow, storm, fog }

    static func sky(_ code: Int) -> Sky {
        switch code {
        case 0, 1: return .clear
        case 2, 3: return .cloudy
        case 45, 48: return .fog
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .storm
        case 51...67, 80...82: return .rain
        default: return .cloudy
        }
    }
}

/// Fetches forecasts from Open-Meteo (free, no API key) for "auto" (current location) or a city name.
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()
    static let autoKey = "auto"

    @Published private(set) var reports: [String: WeatherReport] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var loading: Set<String> = []

    private var clients: [String: Int] = [:]
    private var lastAttempt: [String: Date] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let locator = Locator()

    init() {
        Timer.publish(every: 600, tolerance: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refreshStale() }
            .store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .delay(for: .seconds(5), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStale() }
            .store(in: &cancellables)
    }

    static func key(forCity city: String) -> String {
        let trimmed = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? autoKey : trimmed.lowercased()
    }

    func retain(_ key: String) {
        clients[key, default: 0] += 1
        if clients[key] == 1 { refreshIfStale(key) }
    }

    func release(_ key: String) {
        clients[key] = max(0, (clients[key] ?? 1) - 1)
    }

    func refresh(_ key: String) {
        lastAttempt[key] = nil
        fetch(key)
    }

    private func refreshStale() {
        for (key, count) in clients where count > 0 { refreshIfStale(key) }
    }

    private func refreshIfStale(_ key: String) {
        if let report = reports[key], Date().timeIntervalSince(report.fetched) < 15 * 60 { return }
        if let attempt = lastAttempt[key], Date().timeIntervalSince(attempt) < 60 { return }
        fetch(key)
    }

    private func fetch(_ key: String) {
        lastAttempt[key] = Date()
        loading.insert(key)
        if key == Self.autoKey {
            locator.request { [weak self] result in
                switch result {
                case .success(let location):
                    self?.reverseGeocode(location) { place in
                        self?.fetchForecast(latitude: location.coordinate.latitude,
                                            longitude: location.coordinate.longitude,
                                            place: place, key: key)
                    }
                case .failure(let error):
                    self?.fail(key, error.localizedDescription)
                }
            }
        } else {
            geocode(city: key, key: key)
        }
    }

    private func fail(_ key: String, _ message: String) {
        loading.remove(key)
        errors[key] = message
    }

    private func reverseGeocode(_ location: CLLocation, completion: @escaping (String) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let place = placemarks?.first.flatMap { $0.locality ?? $0.name } ?? "My Location"
            DispatchQueue.main.async { completion(place) }
        }
    }

    private func geocode(city: String, key: String) {
        let query = city.split(separator: ",").first.map(String.init) ?? city
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: query.trimmingCharacters(in: .whitespaces)),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return fail(key, "Invalid city name") }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            let result = data.flatMap { try? JSONDecoder().decode(GeocodeResponse.self, from: $0) }?.results?.first
            DispatchQueue.main.async {
                guard let self else { return }
                guard let result else {
                    self.fail(key, error == nil ? "Couldn't find “\(city)”" : "No internet connection")
                    return
                }
                self.fetchForecast(latitude: result.latitude, longitude: result.longitude, place: result.name, key: key)
            }
        }.resume()
    }

    private func fetchForecast(latitude: Double, longitude: Double, place: String, key: String) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "forecast_days", value: "7"),
        ]
        guard let url = components?.url else { return fail(key, "Invalid location") }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let report = data
                .flatMap { try? JSONDecoder().decode(ForecastResponse.self, from: $0) }
                .flatMap { $0.report(place: place) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(key)
                if let report {
                    self.reports[key] = report
                    self.errors[key] = nil
                } else if self.reports[key] == nil {
                    self.errors[key] = "Weather is unavailable right now"
                }
            }
        }.resume()
    }
}

// MARK: - Open-Meteo responses

private struct GeocodeResponse: Decodable {
    struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
    }
    let results: [Place]?
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let time: Double
        let temperature_2m: Double?
        let apparent_temperature: Double?
        let relative_humidity_2m: Double?
        let weather_code: Double?
        let is_day: Double?
        let wind_speed_10m: Double?
    }

    struct Hourly: Decodable {
        let time: [Double]
        let temperature_2m: [Double?]
        let weather_code: [Double?]
        let is_day: [Double?]
    }

    struct Daily: Decodable {
        let time: [Double]
        let weather_code: [Double?]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let sunrise: [Double?]?
        let sunset: [Double?]?
        let precipitation_probability_max: [Double?]?
    }

    let current: Current?
    let hourly: Hourly?
    let daily: Daily?

    func report(place: String) -> WeatherReport? {
        guard let current, let temperature = current.temperature_2m else { return nil }
        let now = Date()

        var hours: [WeatherReport.Hour] = []
        if let hourly {
            for index in hourly.time.indices {
                let date = Date(timeIntervalSince1970: hourly.time[index])
                guard date > now.addingTimeInterval(-3600),
                      index < hourly.temperature_2m.count, let temp = hourly.temperature_2m[index] else { continue }
                let code = index < hourly.weather_code.count ? Int(hourly.weather_code[index] ?? 0) : 0
                let isDay = index < hourly.is_day.count ? (hourly.is_day[index] ?? 1) > 0 : true
                hours.append(.init(id: hourly.time[index], date: date, temperature: temp, code: code, isDay: isDay))
                if hours.count >= 24 { break }
            }
        }

        var days: [WeatherReport.Day] = []
        var sunrise: Date?
        var sunset: Date?
        if let daily {
            for index in daily.time.indices {
                guard index < daily.temperature_2m_max.count, index < daily.temperature_2m_min.count,
                      let high = daily.temperature_2m_max[index], let low = daily.temperature_2m_min[index] else { continue }
                let code = index < daily.weather_code.count ? Int(daily.weather_code[index] ?? 0) : 0
                let rain = daily.precipitation_probability_max.flatMap { index < $0.count ? $0[index] : nil }
                days.append(.init(id: daily.time[index], date: Date(timeIntervalSince1970: daily.time[index]),
                                  code: code, high: high, low: low, precipitation: rain.map { Int($0) }))
            }
            if let first = daily.sunrise?.first, let value = first { sunrise = Date(timeIntervalSince1970: value) }
            if let first = daily.sunset?.first, let value = first { sunset = Date(timeIntervalSince1970: value) }
        }

        return WeatherReport(place: place,
                             temperature: temperature,
                             apparent: current.apparent_temperature ?? temperature,
                             code: Int(current.weather_code ?? 0),
                             isDay: (current.is_day ?? 1) > 0,
                             humidity: current.relative_humidity_2m.map { Int($0) },
                             wind: current.wind_speed_10m,
                             high: days.first?.high ?? temperature,
                             low: days.first?.low ?? temperature,
                             sunrise: sunrise,
                             sunset: sunset,
                             hours: hours,
                             days: days,
                             fetched: now)
    }
}

// MARK: - Location

enum LocatorError: LocalizedError {
    case unavailable, denied

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Location needs the installed app. Set a city in Edit Widget."
        case .denied: return "Location is off. Set a city in Edit Widget or allow Location in System Settings."
        }
    }
}

final class Locator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var handlers: [(Result<CLLocation, Error>) -> Void] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(_ handler: @escaping (Result<CLLocation, Error>) -> Void) {
        guard Shell.isBundled, Shell.hasUsageDescription("NSLocationUsageDescription") else {
            handler(.failure(LocatorError.unavailable))
            return
        }
        handlers.append(handler)
        guard handlers.count == 1 else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.failure(LocatorError.denied))
        default:
            manager.requestLocation()
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        let pending = handlers
        handlers = []
        DispatchQueue.main.async {
            pending.forEach { $0(result) }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !handlers.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            break
        case .denied, .restricted:
            finish(.failure(LocatorError.denied))
        default:
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(.failure(error))
    }
}

import Foundation
import SwiftUI

enum Fmt {
    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, fraction) * 100).rounded()))%"
    }

    static func memory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .memory)
    }

    static func disk(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Short gigabyte figure, e.g. "18.2".
    static func gigabytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 100 ? String(format: "%.0f", gb) : String(format: "%.1f", gb)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1000 && index < units.count - 1 {
            value /= 1000
            index += 1
        }
        if index == 0 { return "\(Int(value)) B/s" }
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[index])
    }

    static func count(_ value: Int) -> String {
        let number = Double(value)
        switch number {
        case 1_000_000_000...: return String(format: "%.1fB", number / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", number / 1_000_000)
        case 10_000...: return String(format: "%.0fK", number / 1_000)
        case 1_000...: return String(format: "%.1fK", number / 1_000)
        default: return "\(value)"
        }
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    static func uptime(since boot: Date, now: Date = Date()) -> String {
        let minutes = Int(now.timeIntervalSince(boot) / 60)
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// "now", "4m", "2h", "Yesterday", "Mon", "Sep 3"
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600))h ago" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86400 { return DateFormats.string(date, template: "EEE") }
        return DateFormats.string(date, template: "MMMd")
    }

    static func temperature(celsius: Double, unit: TemperatureUnit = AppearanceSettings.shared.temperatureUnit) -> String {
        let value = unit.usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }
}

/// Cached date formatters (creating them is surprisingly expensive).
enum DateFormats {
    private static var cache: [String: DateFormatter] = [:]

    static func formatter(template: String, timeZone: TimeZone = .current) -> DateFormatter {
        let key = "t|\(template)|\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[key] = formatter
        return formatter
    }

    static func formatter(format: String, timeZone: TimeZone = .current) -> DateFormatter {
        let key = "f|\(format)|\(timeZone.identifier)"
        if let cached = cache[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        cache[key] = formatter
        return formatter
    }

    static func string(_ date: Date, template: String, timeZone: TimeZone = .current) -> String {
        formatter(template: template, timeZone: timeZone).string(from: date)
    }

    static func string(_ date: Date, format: String, timeZone: TimeZone = .current) -> String {
        formatter(format: format, timeZone: timeZone).string(from: date)
    }

    /// Time like "9:41" (12h) or "21:41" (24h), without AM/PM.
    static func time(_ date: Date, use24Hour: Bool, seconds: Bool, timeZone: TimeZone = .current) -> String {
        let base = use24Hour ? "HH:mm" : "h:mm"
        return string(date, format: seconds ? base + ":ss" : base, timeZone: timeZone)
    }

    static func meridiem(_ date: Date, timeZone: TimeZone = .current) -> String {
        string(date, format: "a", timeZone: timeZone)
    }

    /// Time with AM/PM in the user's preferred style, e.g. "3:30 PM".
    static func shortTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        string(date, template: "jmm", timeZone: timeZone)
    }
}

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let cpu = Color.blue
    static let gpu = Color.purple
    static let memory = Color.green
    static let disk = Color.orange
    static let download = Color.cyan
    static let upload = Color.pink
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

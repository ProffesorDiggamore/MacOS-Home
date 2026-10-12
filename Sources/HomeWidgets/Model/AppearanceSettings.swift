import SwiftUI
import AppKit

enum WidgetStyle: String, Codable, CaseIterable, Identifiable {
    case glass, liquidGlass, solid, tinted, clear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Frosted Glass"
        case .liquidGlass: return "Liquid Glass"
        case .solid: return "Solid"
        case .tinted: return "Tinted"
        case .clear: return "Clear"
        }
    }

    /// Liquid Glass needs macOS 26; everything else works everywhere.
    static var available: [WidgetStyle] {
        if #available(macOS 26.0, *) { return allCases }
        return allCases.filter { $0 != .liquidGlass }
    }

    /// Colors used for charts and icons. Tinted widgets keep everything white so it reads on the color.
    func tone(_ color: Color) -> Color {
        self == .tinted ? .white : color
    }
}

enum SchemeOption: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

enum AccentOption: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, teal, graphite

    var id: String { rawValue }
    var label: String { self == .system ? "System Accent" : rawValue.capitalized }

    var color: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        case .graphite: return Color(white: 0.45)
        }
    }
}

enum FontOption: String, CaseIterable, Identifiable {
    case standard, rounded, serif
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "SF Pro"
        case .rounded: return "SF Rounded"
        case .serif: return "New York"
        }
    }
    var design: Font.Design {
        switch self {
        case .standard: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        }
    }
}

enum WidgetLayer: String, CaseIterable, Identifiable {
    case desktop, floating
    var id: String { rawValue }
    var label: String {
        switch self {
        case .desktop: return "On the desktop (behind windows)"
        case .floating: return "Floating (above windows)"
        }
    }
    var windowLevel: NSWindow.Level {
        switch self {
        case .desktop: return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .floating: return .floating
        }
    }
}

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case system, celsius, fahrenheit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match Region"
        case .celsius: return "Celsius (°C)"
        case .fahrenheit: return "Fahrenheit (°F)"
        }
    }
    var usesFahrenheit: Bool {
        switch self {
        case .celsius: return false
        case .fahrenheit: return true
        case .system: return Locale.current.measurementSystem == .us
        }
    }
}

/// Global look & behavior settings, persisted in UserDefaults.
final class AppearanceSettings: ObservableObject {
    static let shared = AppearanceSettings()
    private let defaults = UserDefaults.standard

    @Published var style: WidgetStyle { didSet { defaults.set(style.rawValue, forKey: "style") } }
    @Published var scheme: SchemeOption { didSet { defaults.set(scheme.rawValue, forKey: "scheme") } }
    @Published var accent: AccentOption { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    @Published var font: FontOption { didSet { defaults.set(font.rawValue, forKey: "font") } }
    @Published var backgroundOpacity: Double { didSet { defaults.set(backgroundOpacity, forKey: "backgroundOpacity") } }
    @Published var showShadow: Bool { didSet { defaults.set(showShadow, forKey: "showShadow") } }
    @Published var layer: WidgetLayer { didSet { defaults.set(layer.rawValue, forKey: "layer") } }
    @Published var locked: Bool { didSet { defaults.set(locked, forKey: "locked") } }
    @Published var hidden: Bool { didSet { defaults.set(hidden, forKey: "hidden") } }
    @Published var refreshInterval: Double { didSet { defaults.set(refreshInterval, forKey: "refreshInterval") } }
    @Published var temperatureUnit: TemperatureUnit { didSet { defaults.set(temperatureUnit.rawValue, forKey: "temperatureUnit") } }

    init() {
        style = WidgetStyle(rawValue: defaults.string(forKey: "style") ?? "") ?? .glass
        scheme = SchemeOption(rawValue: defaults.string(forKey: "scheme") ?? "") ?? .system
        accent = AccentOption(rawValue: defaults.string(forKey: "accent") ?? "") ?? .system
        font = FontOption(rawValue: defaults.string(forKey: "font") ?? "") ?? .standard
        backgroundOpacity = defaults.object(forKey: "backgroundOpacity") as? Double ?? 1.0
        showShadow = defaults.object(forKey: "showShadow") as? Bool ?? true
        layer = WidgetLayer(rawValue: defaults.string(forKey: "layer") ?? "") ?? .desktop
        locked = defaults.bool(forKey: "locked")
        hidden = defaults.bool(forKey: "hidden")
        refreshInterval = defaults.object(forKey: "refreshInterval") as? Double ?? 1.0
        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: "temperatureUnit") ?? "") ?? .system
    }

    var accentColor: Color { accent.color }

    func resetLook() {
        style = .glass
        scheme = .system
        accent = .system
        font = .standard
        backgroundOpacity = 1
        showShadow = true
    }
}

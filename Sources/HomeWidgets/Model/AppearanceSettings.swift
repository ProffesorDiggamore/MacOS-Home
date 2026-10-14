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

/// How a widget's graphs, rings and icons are coloured.
enum WidgetColorMode: String, CaseIterable, Identifiable, Codable {
    case theme, single, original

    var id: String { rawValue }
    var label: String {
        switch self {
        case .theme: return "Theme"
        case .single: return "One Color"
        case .original: return "Original (many colors)"
        }
    }

    /// Reads saved values, including version 3.0's "trio" (now the default theme).
    init?(stored: String) {
        if stored == "trio" { self = .theme } else { self.init(rawValue: stored) }
    }
}

/// A theme is five colours. Every colour a widget uses falls into one of these
/// families, so changing a slot recolours it in every widget at once.
enum ThemeSlot: Int, CaseIterable, Identifiable {
    case reds, warms, greens, blues, purples

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .reds: return "Reds & pinks"
        case .warms: return "Oranges & yellows"
        case .greens: return "Greens & mints"
        case .blues: return "Blues & teals"
        case .purples: return "Purples & indigos"
        }
    }
    /// Where you'll see it, so it's clear what each slot changes.
    var usedBy: String {
        switch self {
        case .reds: return "Calendar, alerts, low battery"
        case .warms: return "Storage, timers, weather sun"
        case .greens: return "Memory, battery, habits"
        case .blues: return "CPU, network, Wi-Fi"
        case .purples: return "GPU, GitHub, clipboard"
        }
    }
    /// The colour widgets were designed with, shown next to each slot.
    var original: Color {
        switch self {
        case .reds: return .red
        case .warms: return .orange
        case .greens: return .green
        case .blues: return .blue
        case .purples: return .purple
        }
    }

    /// Which family a hue (in degrees) belongs to.
    static func slot(hue: Double) -> ThemeSlot {
        switch hue {
        case 15..<75: return .warms
        case 75..<170: return .greens
        case 170..<255: return .blues
        case 255..<330: return .purples
        default: return .reds
        }
    }
}

struct ThemePreset: Identifiable {
    let name: String
    let colors: [String] // one per ThemeSlot, RRGGBB
    var id: String { name }

    static let all: [ThemePreset] = [
        ThemePreset(name: "Green · Yellow · Blue", colors: ["FFCC00", "FFCC00", "34C759", "0A84FF", "0A84FF"]),
        ThemePreset(name: "Apple", colors: ["FF3B30", "FF9500", "34C759", "007AFF", "AF52DE"]),
        ThemePreset(name: "Ocean", colors: ["5AC8FA", "64D2FF", "30D5C8", "0A84FF", "5E5CE6"]),
        ThemePreset(name: "Sunset", colors: ["FF2D55", "FF9F0A", "FFD60A", "FF6B6B", "BF5AF2"]),
        ThemePreset(name: "Neon", colors: ["FF2D95", "FFE600", "39FF14", "00E5FF", "B026FF"]),
        ThemePreset(name: "Forest", colors: ["D97757", "E9C46A", "52B788", "2A9D8F", "6A994E"]),
        ThemePreset(name: "Pastel", colors: ["FFADAD", "FFD6A5", "CAFFBF", "9BF6FF", "BDB2FF"]),
        ThemePreset(name: "Fire", colors: ["FF3B30", "FF9500", "FFCC00", "FF6B35", "FF2D55"]),
        ThemePreset(name: "Ice", colors: ["E0F2FE", "BAE6FD", "7DD3FC", "38BDF8", "818CF8"]),
        ThemePreset(name: "Mono", colors: ["F2F2F7", "F2F2F7", "F2F2F7", "F2F2F7", "F2F2F7"]),
    ]

    static let standard = all[0].colors
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
    @Published var showInDock: Bool { didSet { defaults.set(showInDock, forKey: "showInDock") } }
    @Published var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
    @Published var colorMode: WidgetColorMode { didSet { defaults.set(colorMode.rawValue, forKey: "colorMode") } }
    /// The theme's five colours (one per ThemeSlot), RRGGBB.
    @Published var themeColors: [String] { didSet { defaults.set(themeColors, forKey: "themeColors") } }
    /// The colour used when `colorMode` is `.single`, as RRGGBB.
    @Published var singleColor: String { didSet { defaults.set(singleColor, forKey: "singleColor") } }

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
        showInDock = defaults.object(forKey: "showInDock") as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        colorMode = WidgetColorMode(stored: defaults.string(forKey: "colorMode") ?? "") ?? .theme
        let savedTheme = defaults.stringArray(forKey: "themeColors") ?? []
        themeColors = savedTheme.count == ThemeSlot.allCases.count ? savedTheme : ThemePreset.standard
        singleColor = defaults.string(forKey: "singleColor") ?? "34C759"
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

import SwiftUI

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// Side length of a small widget, matching the proportions of Apple's desktop widgets.
    static let unit: CGFloat = 164
    static let spacing: CGFloat = 16

    var dimensions: CGSize {
        let wide = WidgetSize.unit * 2 + WidgetSize.spacing
        switch self {
        case .small: return CGSize(width: WidgetSize.unit, height: WidgetSize.unit)
        case .medium: return CGSize(width: wide, height: WidgetSize.unit)
        case .large: return CGSize(width: wide, height: wide)
        }
    }
}

enum WidgetCategory: String, CaseIterable, Identifiable {
    case time, system, productivity, fun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: return "Time & Date"
        case .system: return "System"
        case .productivity: return "Productivity"
        case .fun: return "Media & Inspiration"
        }
    }
}

enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    // Time & Date
    case clock, analogClock, worldClock, calendar, countdown, yearProgress
    // System
    case systemStats, cpu, gpu, memory, storage, network, battery, topProcesses, systemInfo
    // Productivity
    case claude, appShortcuts, quickActions, reminders, focusTimer, note, folder, weather
    // Media & Inspiration
    case nowPlaying, photo, verse, moonPhase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .analogClock: return "Analog Clock"
        case .worldClock: return "World Clock"
        case .calendar: return "Calendar"
        case .countdown: return "Countdown"
        case .yearProgress: return "Year Progress"
        case .systemStats: return "System Stats"
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .memory: return "Memory"
        case .storage: return "Storage"
        case .network: return "Network"
        case .battery: return "Battery"
        case .topProcesses: return "Top Processes"
        case .systemInfo: return "About This Mac"
        case .claude: return "Claude Code"
        case .appShortcuts: return "App Shortcuts"
        case .quickActions: return "Quick Actions"
        case .reminders: return "Reminders"
        case .focusTimer: return "Focus Timer"
        case .note: return "Sticky Note"
        case .folder: return "Folder"
        case .weather: return "Weather"
        case .nowPlaying: return "Now Playing"
        case .photo: return "Photo"
        case .verse: return "Verse of the Day"
        case .moonPhase: return "Moon Phase"
        }
    }

    var summary: String {
        switch self {
        case .clock: return "The time in big, beautiful type."
        case .analogClock: return "A classic clock face with a sweeping second hand."
        case .worldClock: return "Keep track of time in other cities."
        case .calendar: return "Today's date, the month, and what's coming up."
        case .countdown: return "Count the days until something you're excited about."
        case .yearProgress: return "See how much of the year has gone by."
        case .systemStats: return "CPU, GPU, memory and storage at a glance."
        case .cpu: return "Live processor usage with history and per-core load."
        case .gpu: return "Live graphics processor usage."
        case .memory: return "How much RAM is in use and memory pressure."
        case .storage: return "Free space on your disks."
        case .network: return "Live upload and download speed."
        case .battery: return "Charge, health, cycles and power draw."
        case .topProcesses: return "The apps using the most CPU or memory."
        case .systemInfo: return "Your Mac's chip, macOS version and uptime."
        case .claude: return "Your Claude Code sessions: who's working and who's waiting on you."
        case .appShortcuts: return "One-click launchers for your favorite apps."
        case .quickActions: return "Lock screen, dark mode, screenshots and your Shortcuts."
        case .reminders: return "Check off reminders right from the desktop."
        case .focusTimer: return "A Pomodoro-style focus and break timer."
        case .note: return "A sticky note you can type into."
        case .folder: return "Recent files from Downloads or any folder."
        case .weather: return "Current conditions and the forecast."
        case .nowPlaying: return "What's playing in Music or Spotify, with controls."
        case .photo: return "A favorite photo, or a slideshow from a folder."
        case .verse: return "A Bible verse to start your day (KJV)."
        case .moonPhase: return "Tonight's moon and the next full moon."
        }
    }

    var symbol: String {
        switch self {
        case .clock: return "clock.fill"
        case .analogClock: return "clock"
        case .worldClock: return "globe"
        case .calendar: return "calendar"
        case .countdown: return "hourglass"
        case .yearProgress: return "chart.bar.fill"
        case .systemStats: return "gauge.with.dots.needle.67percent"
        case .cpu: return "cpu"
        case .gpu: return "cube.fill"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .battery: return "battery.100percent.bolt"
        case .topProcesses: return "list.bullet.rectangle"
        case .systemInfo: return "apple.logo"
        case .claude: return "sparkles"
        case .appShortcuts: return "square.grid.3x3.fill"
        case .quickActions: return "bolt.circle.fill"
        case .reminders: return "checklist"
        case .focusTimer: return "timer"
        case .note: return "note.text"
        case .folder: return "folder.fill"
        case .weather: return "cloud.sun.fill"
        case .nowPlaying: return "music.note"
        case .photo: return "photo.fill"
        case .verse: return "book.closed.fill"
        case .moonPhase: return "moon.stars.fill"
        }
    }

    var tint: Color {
        switch self {
        case .clock, .analogClock, .worldClock: return .orange
        case .calendar, .countdown: return .red
        case .yearProgress: return .pink
        case .systemStats, .cpu: return .blue
        case .gpu: return .purple
        case .memory: return .green
        case .storage: return .orange
        case .network: return .teal
        case .battery: return .green
        case .topProcesses, .systemInfo: return .gray
        case .claude: return Palette.claude
        case .appShortcuts: return .indigo
        case .quickActions: return .yellow
        case .reminders: return .orange
        case .focusTimer: return .red
        case .note: return .yellow
        case .folder: return .blue
        case .weather: return .cyan
        case .nowPlaying: return .pink
        case .photo: return .mint
        case .verse: return .brown
        case .moonPhase: return .indigo
        }
    }

    var category: WidgetCategory {
        switch self {
        case .clock, .analogClock, .worldClock, .calendar, .countdown, .yearProgress:
            return .time
        case .systemStats, .cpu, .gpu, .memory, .storage, .network, .battery, .topProcesses, .systemInfo:
            return .system
        case .claude, .appShortcuts, .quickActions, .reminders, .focusTimer, .note, .folder, .weather:
            return .productivity
        case .nowPlaying, .photo, .verse, .moonPhase:
            return .fun
        }
    }

    var sizes: [WidgetSize] {
        switch self {
        case .battery, .nowPlaying, .countdown, .focusTimer, .moonPhase, .systemInfo:
            return [.small, .medium]
        case .topProcesses:
            return [.medium, .large]
        default:
            return WidgetSize.allCases
        }
    }

    var defaultSize: WidgetSize {
        switch self {
        case .claude, .appShortcuts, .systemStats, .topProcesses, .worldClock, .verse, .network:
            return .medium
        default:
            return .small
        }
    }
}

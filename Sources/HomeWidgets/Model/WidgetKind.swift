import SwiftUI

/// The three layouts widgets design for. Extra shapes reuse the closest one.
enum WidgetFamily {
    case small, medium, large
}

enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large, tall, wide, extraLarge, portrait

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .tall: return "Tall"
        case .wide: return "Wide"
        case .extraLarge: return "Extra Large"
        case .portrait: return "Portrait"
        }
    }

    /// Grid cells (columns × rows) this size takes up.
    var cells: (columns: Int, rows: Int) {
        switch self {
        case .small: return (1, 1)
        case .medium: return (2, 1)
        case .large: return (2, 2)
        case .tall: return (1, 2)
        case .wide: return (4, 1)
        case .extraLarge: return (4, 2)
        case .portrait: return (2, 3)
        }
    }

    var family: WidgetFamily {
        switch self {
        case .small, .tall: return .small
        case .medium, .wide: return .medium
        case .large, .extraLarge, .portrait: return .large
        }
    }

    /// Side length of a small widget, matching the proportions of Apple's desktop widgets.
    static let unit: CGFloat = 164
    static let spacing: CGFloat = 16

    var dimensions: CGSize {
        let (columns, rows) = cells
        return CGSize(width: CGFloat(columns) * WidgetSize.unit + CGFloat(columns - 1) * WidgetSize.spacing,
                      height: CGFloat(rows) * WidgetSize.unit + CGFloat(rows - 1) * WidgetSize.spacing)
    }

    static let standard: [WidgetSize] = [.small, .medium, .large]
}

enum WidgetCategory: String, CaseIterable, Identifiable {
    case time, planner, system, tools, productivity, web, media, fun

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: return "Time & Date"
        case .planner: return "School & Planning"
        case .system: return "System"
        case .tools: return "Tools"
        case .productivity: return "Productivity"
        case .web: return "Accounts & Web"
        case .media: return "Photos, Text & Media"
        case .fun: return "Fun & Aesthetic"
        }
    }
}

/// Everything the gallery needs to know about a kind of widget.
struct WidgetKindInfo {
    let title: String
    let summary: String
    let symbol: String
    let tint: Color
    let category: WidgetCategory
    var sizes: [WidgetSize] = WidgetSize.standard
    var defaultSize: WidgetSize = .small
}

enum WidgetKind: String, CaseIterable, Identifiable, Codable {
    // Time & Date
    case clock, analogClock, worldClock, calendar, countdown, yearProgress
    case flipClock, wordClock, binaryClock, stopwatch, sunArc
    // System
    case systemStats, cpu, gpu, memory, storage, network, battery, topProcesses, systemInfo
    case diskActivity, wifi, volume, clipboard
    // Productivity
    case claude, appShortcuts, quickActions, reminders, focusTimer, note, folder, weather
    case todo, habits, links, calculator, counter
    // Accounts & Web
    case github, contributions, cairn, mail, news, hackerNews, stocks, crypto, currency, sports, uptime, serviceStatus
    // Photos, Text & Media
    case nowPlaying, photo, sticker, text, verse, moonPhase
    // Fun & Aesthetic
    case crabPet, lifeGame
    // Version 3
    case monthCalendar, upNext, agenda, classSchedule, homework, readingPlan
    case timer, webSearch, dictionary, converter, qrCode, password, colorPicker, recentFiles, screenshots
    case soundOutput, microphone, keepAwake, ipAddress, internet
    case airQuality, githubRepo, water, quote, bigDate, timeRings
    case breathe
    // Version 4
    case dotClock, devServers, gitStatus, devTools, onThisDay, deviceBatteries
    // Version 5
    case slateToday, slateStreak, ciRuns
    // Version 6
    case claudeBudget

    var id: String { rawValue }

    var info: WidgetKindInfo {
        let smallMedium: [WidgetSize] = [.small, .medium]
        let mediumLarge: [WidgetSize] = [.medium, .large]
        let flexible = WidgetSize.allCases
        let roomy: [WidgetSize] = [.medium, .large, .wide, .extraLarge, .portrait]
        switch self {
        // Time & Date
        case .clock:
            return .init(title: "Clock", summary: "The time in big, beautiful type.", symbol: "clock.fill", tint: .orange, category: .time, sizes: flexible)
        case .analogClock:
            return .init(title: "Analog Clock", summary: "A classic clock face with a sweeping second hand.", symbol: "clock", tint: .orange, category: .time, sizes: flexible)
        case .worldClock:
            return .init(title: "World Clock", summary: "Keep track of time in other cities.", symbol: "globe", tint: .orange, category: .time, sizes: flexible, defaultSize: .medium)
        case .calendar:
            return .init(title: "Calendar", summary: "Today's date, the month, and what's coming up.", symbol: "calendar", tint: .red, category: .time)
        case .countdown:
            return .init(title: "Countdown", summary: "Count the days until something you're excited about.", symbol: "hourglass", tint: .red, category: .time, sizes: smallMedium)
        case .yearProgress:
            return .init(title: "Year Progress", summary: "See how much of the year has gone by.", symbol: "chart.bar.fill", tint: .pink, category: .time, sizes: flexible)
        case .flipClock:
            return .init(title: "Flip Clock", summary: "A retro split-flap clock.", symbol: "rectangle.split.2x1.fill", tint: .gray, category: .time, sizes: smallMedium, defaultSize: .medium)
        case .wordClock:
            return .init(title: "Word Clock", summary: "Tells the time in words, like a QLOCKTWO.", symbol: "textformat.abc", tint: .teal, category: .time)
        case .binaryClock:
            return .init(title: "Binary Clock", summary: "The time in ones and zeros. Very nerdy.", symbol: "circle.grid.3x3.fill", tint: .green, category: .time, sizes: smallMedium)
        case .stopwatch:
            return .init(title: "Stopwatch", summary: "Start, stop and lap timer.", symbol: "stopwatch.fill", tint: .orange, category: .time, sizes: smallMedium)
        case .sunArc:
            return .init(title: "Sun", summary: "Where the sun is in the sky, with sunrise and sunset.", symbol: "sun.horizon.fill", tint: .yellow, category: .time, sizes: smallMedium, defaultSize: .medium)

        // System
        case .systemStats:
            return .init(title: "System Stats", summary: "CPU, GPU, memory and storage at a glance.", symbol: "gauge.with.dots.needle.67percent", tint: .blue, category: .system, defaultSize: .medium)
        case .cpu:
            return .init(title: "CPU", summary: "Live processor usage with history and per-core load.", symbol: "cpu", tint: .blue, category: .system)
        case .gpu:
            return .init(title: "GPU", summary: "Live graphics processor usage.", symbol: "cube.fill", tint: .purple, category: .system)
        case .memory:
            return .init(title: "Memory", summary: "How much RAM is in use and memory pressure.", symbol: "memorychip", tint: .green, category: .system)
        case .storage:
            return .init(title: "Storage", summary: "Free space on your disks.", symbol: "internaldrive", tint: .orange, category: .system)
        case .network:
            return .init(title: "Network", summary: "Live upload and download speed.", symbol: "network", tint: .teal, category: .system, defaultSize: .medium)
        case .battery:
            return .init(title: "Battery", summary: "Charge, health, cycles and power draw.", symbol: "battery.100percent.bolt", tint: .green, category: .system, sizes: smallMedium)
        case .topProcesses:
            return .init(title: "Top Processes", summary: "The apps using the most CPU or memory.", symbol: "list.bullet.rectangle", tint: .gray, category: .system, sizes: mediumLarge, defaultSize: .medium)
        case .systemInfo:
            return .init(title: "About This Mac", summary: "Your Mac's chip, macOS version and uptime.", symbol: "apple.logo", tint: .gray, category: .system, sizes: smallMedium)
        case .diskActivity:
            return .init(title: "Disk Activity", summary: "How fast your SSD is reading and writing.", symbol: "externaldrive.fill.badge.timemachine", tint: .orange, category: .system)
        case .wifi:
            return .init(title: "Wi-Fi", summary: "Signal strength, speed and channel.", symbol: "wifi", tint: .blue, category: .system, sizes: smallMedium)
        case .volume:
            return .init(title: "Volume", summary: "A volume slider and mute button.", symbol: "speaker.wave.2.fill", tint: .pink, category: .system, sizes: smallMedium)
        case .clipboard:
            return .init(title: "Clipboard History", summary: "The last things you copied. Click one to copy it again.", symbol: "doc.on.clipboard.fill", tint: .indigo, category: .system, sizes: roomy, defaultSize: .medium)

        // Productivity
        case .claude:
            return .init(title: "Claude Code", summary: "Your Claude Code sessions, or the little Claude crab.", symbol: "sparkles", tint: Palette.claude, category: .productivity, sizes: flexible, defaultSize: .medium)
        case .appShortcuts:
            return .init(title: "App Shortcuts", summary: "One-click launchers for your favorite apps.", symbol: "square.grid.3x3.fill", tint: .indigo, category: .productivity, sizes: flexible, defaultSize: .medium)
        case .quickActions:
            return .init(title: "Quick Actions", summary: "Lock screen, dark mode, screenshots and your Shortcuts.", symbol: "bolt.circle.fill", tint: .yellow, category: .productivity, sizes: flexible)
        case .reminders:
            return .init(title: "Reminders", summary: "Check off reminders right from the desktop.", symbol: "checklist", tint: .orange, category: .productivity)
        case .focusTimer:
            return .init(title: "Focus Timer", summary: "A Pomodoro-style focus and break timer.", symbol: "timer", tint: .red, category: .productivity, sizes: smallMedium)
        case .note:
            return .init(title: "Sticky Note", summary: "A sticky note you can type into.", symbol: "note.text", tint: .yellow, category: .productivity, sizes: flexible)
        case .folder:
            return .init(title: "Folder", summary: "Recent files from Downloads or any folder.", symbol: "folder.fill", tint: .blue, category: .productivity)
        case .weather:
            return .init(title: "Weather", summary: "Current conditions and the forecast.", symbol: "cloud.sun.fill", tint: .cyan, category: .productivity, sizes: flexible)
        case .todo:
            return .init(title: "To-Do List", summary: "A quick checklist. Type to add, click to check off.", symbol: "checkmark.circle.fill", tint: .blue, category: .productivity, sizes: flexible)
        case .habits:
            return .init(title: "Habits", summary: "Track daily habits and keep your streaks going.", symbol: "flame.fill", tint: .orange, category: .productivity, sizes: mediumLarge, defaultSize: .medium)
        case .links:
            return .init(title: "Quick Links", summary: "Your favorite websites, one click away.", symbol: "link", tint: .blue, category: .productivity, sizes: flexible)
        case .calculator:
            return .init(title: "Calculator", summary: "A tiny calculator that lives on your desktop.", symbol: "plus.forwardslash.minus", tint: .orange, category: .productivity, sizes: [.small, .large])
        case .counter:
            return .init(title: "Counter", summary: "Tap to count anything: pushups, water, laps.", symbol: "plus.circle.fill", tint: .green, category: .productivity, sizes: smallMedium)

        // Accounts & Web
        case .github:
            return .init(title: "GitHub", summary: "Pull requests waiting on you, your PRs and notifications.", symbol: "chevron.left.forwardslash.chevron.right", tint: .purple, category: .web, sizes: flexible, defaultSize: .medium)
        case .contributions:
            return .init(title: "Contributions", summary: "Your GitHub contribution graph and streak.", symbol: "square.grid.4x3.fill", tint: .green, category: .web, sizes: flexible, defaultSize: .medium)
        case .cairn:
            return .init(title: "Slate Notes", summary: "Recent notes, today's page and quick capture from your Slate notes repo on GitHub.", symbol: "square.stack.3d.up.fill", tint: Slate.stone, category: .web, sizes: flexible, defaultSize: .medium)
        case .mail:
            return .init(title: "Mail", summary: "Unread email from Gmail, iCloud or any account in the Mail app.", symbol: "envelope.fill", tint: .blue, category: .web, sizes: flexible)
        case .news:
            return .init(title: "News Feed", summary: "Headlines from any RSS feed or blog.", symbol: "newspaper.fill", tint: .red, category: .web, sizes: roomy, defaultSize: .medium)
        case .hackerNews:
            return .init(title: "Hacker News", summary: "Top stories on Hacker News.", symbol: "y.square.fill", tint: .orange, category: .web, sizes: roomy, defaultSize: .medium)
        case .stocks:
            return .init(title: "Stocks", summary: "Your watchlist with today's charts.", symbol: "chart.line.uptrend.xyaxis", tint: .green, category: .web, sizes: flexible, defaultSize: .medium)
        case .crypto:
            return .init(title: "Crypto", summary: "Bitcoin, Ethereum and more with today's charts.", symbol: "bitcoinsign.circle.fill", tint: .orange, category: .web, sizes: flexible)
        case .currency:
            return .init(title: "Currency", summary: "Exchange rates from your money to others.", symbol: "dollarsign.arrow.circlepath", tint: .green, category: .web, sizes: smallMedium)
        case .sports:
            return .init(title: "Sports Scores", summary: "Live scores for the NFL, NBA, MLB, NHL, college and soccer.", symbol: "sportscourt.fill", tint: .orange, category: .web, sizes: roomy, defaultSize: .medium)
        case .uptime:
            return .init(title: "Website Monitor", summary: "Checks that your websites are up.", symbol: "antenna.radiowaves.left.and.right", tint: .green, category: .web)
        case .serviceStatus:
            return .init(title: "Service Status", summary: "Is Claude, GitHub or Discord having problems?", symbol: "checkmark.shield.fill", tint: .green, category: .web)

        // Photos, Text & Media
        case .nowPlaying:
            return .init(title: "Now Playing", summary: "What's playing in Music or Spotify, with controls.", symbol: "music.note", tint: .pink, category: .media, sizes: smallMedium)
        case .photo:
            return .init(title: "Photo", summary: "Your photos with frames, or a slideshow. Drag photos onto it.", symbol: "photo.fill", tint: .mint, category: .media, sizes: flexible)
        case .sticker:
            return .init(title: "Sticker", summary: "Any image floating on your desktop, no box around it.", symbol: "face.smiling.inverse", tint: .yellow, category: .media, sizes: flexible)
        case .text:
            return .init(title: "Text", summary: "Your own words or emoji in big, styled type.", symbol: "textformat", tint: .purple, category: .media, sizes: flexible)
        case .verse:
            return .init(title: "Verse of the Day", summary: "A Bible verse to start your day (KJV).", symbol: "book.closed.fill", tint: .brown, category: .media, sizes: flexible, defaultSize: .medium)
        case .moonPhase:
            return .init(title: "Moon Phase", summary: "Tonight's moon and the next full moon.", symbol: "moon.stars.fill", tint: .indigo, category: .media, sizes: smallMedium)

        // Fun & Aesthetic
        case .crabPet:
            return .init(title: "Claude Crab", summary: "A little Claude crab that walks around your desktop.", symbol: "ant.fill", tint: Palette.claude, category: .fun, sizes: flexible, defaultSize: .medium)
        case .lifeGame:
            return .init(title: "Game of Life", summary: "Conway's cellular automaton, evolving forever.", symbol: "square.grid.3x3.middle.filled", tint: .mint, category: .fun, sizes: flexible)

        // School & Planning
        case .monthCalendar:
            return .init(title: "Month", summary: "The whole month, with dots on days that have events.", symbol: "calendar", tint: .red, category: .planner, sizes: [.small, .medium, .large], defaultSize: .small)
        case .upNext:
            return .init(title: "Up Next", summary: "Your next event with a countdown and a Join button for video calls.", symbol: "calendar.badge.clock", tint: .red, category: .planner, sizes: [.small, .medium, .large, .tall])
        case .agenda:
            return .init(title: "This Week", summary: "Everything on your calendar for the next seven days.", symbol: "list.bullet.rectangle.portrait.fill", tint: .red, category: .planner, sizes: [.medium, .large, .tall, .portrait], defaultSize: .tall)
        case .classSchedule:
            return .init(title: "Class Schedule", summary: "What class you're in now, how long is left, and what's next.", symbol: "graduationcap.fill", tint: .indigo, category: .planner, sizes: [.small, .medium, .large, .tall])
        case .homework:
            return .init(title: "Homework", summary: "Assignments by due date. Type “Essay fri” to add one.", symbol: "backpack.fill", tint: .orange, category: .planner, sizes: [.small, .medium, .large, .tall], defaultSize: .medium)
        case .readingPlan:
            return .init(title: "Bible Reading Plan", summary: "Today's chapters for reading the Bible in a year (or the New Testament, Gospels, Psalms).", symbol: "book.fill", tint: .brown, category: .planner, sizes: [.small, .medium])

        // Tools
        case .timer:
            return .init(title: "Timer", summary: "A kitchen-style countdown with one-click presets. Rings even when hidden.", symbol: "timer", tint: .orange, category: .tools, sizes: [.small, .medium])
        case .webSearch:
            return .init(title: "Web Search", summary: "Search Google, YouTube, Wikipedia, Claude or Maps from the desktop.", symbol: "magnifyingglass", tint: .blue, category: .tools, sizes: [.small, .medium, .wide], defaultSize: .medium)
        case .dictionary:
            return .init(title: "Dictionary", summary: "Look up any word offline, plus a word of the day.", symbol: "character.book.closed.fill", tint: .brown, category: .tools, sizes: [.small, .medium, .large, .tall], defaultSize: .medium)
        case .converter:
            return .init(title: "Unit Converter", summary: "Length, weight, temperature, volume, speed, data and time.", symbol: "arrow.left.arrow.right", tint: .teal, category: .tools, sizes: [.small, .medium])
        case .qrCode:
            return .init(title: "QR Code", summary: "Turns whatever link you copied into a QR code for your phone.", symbol: "qrcode", tint: .gray, category: .tools, sizes: [.small, .medium, .large])
        case .password:
            return .init(title: "Password Generator", summary: "Strong random passwords, one click to copy.", symbol: "key.fill", tint: .green, category: .tools, sizes: [.small, .medium])
        case .colorPicker:
            return .init(title: "Color Picker", summary: "Grab any colour on screen and copy its hex code.", symbol: "eyedropper", tint: .pink, category: .tools, sizes: [.small, .medium])
        case .recentFiles:
            return .init(title: "Recent Files", summary: "Files you just changed in Desktop, Documents and Downloads. Drag them anywhere.", symbol: "clock.arrow.circlepath", tint: .blue, category: .tools, sizes: [.small, .medium, .large], defaultSize: .medium)
        case .screenshots:
            return .init(title: "Screenshots", summary: "Your latest screenshots, ready to drag into a message.", symbol: "camera.viewfinder", tint: .purple, category: .tools, sizes: [.small, .medium, .large], defaultSize: .medium)

        // System (v3)
        case .soundOutput:
            return .init(title: "Sound Output", summary: "Switch between speakers, AirPods and displays in one click.", symbol: "hifispeaker.2.fill", tint: .pink, category: .system, sizes: [.small, .medium, .large], defaultSize: .medium)
        case .microphone:
            return .init(title: "Microphone", summary: "A big mute button for calls, plus input level.", symbol: "mic.fill", tint: .green, category: .system, sizes: [.small, .medium])
        case .keepAwake:
            return .init(title: "Keep Awake", summary: "Stops your Mac from sleeping, for a while or until you say so.", symbol: "cup.and.saucer.fill", tint: .brown, category: .system, sizes: [.small, .medium])
        case .ipAddress:
            return .init(title: "IP Address", summary: "Your local and public IP address. Click to copy.", symbol: "network", tint: .teal, category: .system, sizes: [.small, .medium])
        case .internet:
            return .init(title: "Internet", summary: "Is the internet OK? Live latency with a history graph.", symbol: "globe", tint: .green, category: .system, sizes: [.small, .medium])

        // Web, daily & media (v3)
        case .airQuality:
            return .init(title: "Air Quality", summary: "Today's air quality index, PM2.5 and UV where you are.", symbol: "aqi.medium", tint: .mint, category: .web, sizes: [.small, .medium])
        case .githubRepo:
            return .init(title: "GitHub Repo", summary: "Stars, forks, issues and the latest commit for any repo.", symbol: "shippingbox.fill", tint: .purple, category: .web, sizes: [.small, .medium])
        case .water:
            return .init(title: "Water", summary: "Count glasses of water toward a daily goal.", symbol: "drop.fill", tint: .cyan, category: .productivity, sizes: [.small, .medium])
        case .quote:
            return .init(title: "Quote of the Day", summary: "A short, encouraging quote every morning.", symbol: "quote.opening", tint: .gray, category: .media, sizes: [.small, .medium, .wide], defaultSize: .medium)
        case .bigDate:
            return .init(title: "Big Date", summary: "Today's date in huge, beautiful type.", symbol: "textformat.size.larger", tint: .red, category: .time, sizes: [.small, .medium])
        case .timeRings:
            return .init(title: "Time Rings", summary: "How much of the day, week, month and year is done — as activity rings.", symbol: "circle.circle", tint: .pink, category: .time, sizes: [.small, .medium])

        case .breathe:
            return .init(title: "Breathe", summary: "A calming breathing guide that floats on your wallpaper. Click to start.", symbol: "wind", tint: .cyan, category: .fun, sizes: [.small, .medium, .large])

        // Version 4
        case .dotClock:
            return .init(title: "Dot Clock", summary: "The time in glowing LED dots, like a dot-matrix sign.", symbol: "circle.grid.2x2.fill", tint: .orange, category: .time, sizes: [.small, .medium, .wide, .large], defaultSize: .medium)
        case .devServers:
            return .init(title: "Dev Servers", summary: "Everything running on a localhost port. Click one to open it.", symbol: "server.rack", tint: .green, category: .system, sizes: [.small, .medium, .large, .tall], defaultSize: .medium)
        case .gitStatus:
            return .init(title: "Git Status", summary: "Branch, changes and last commit for a repo on your Mac.", symbol: "arrow.triangle.branch", tint: .orange, category: .productivity, sizes: [.small, .medium, .large], defaultSize: .medium)
        case .devTools:
            return .init(title: "Dev Toolkit", summary: "Live Unix time, ISO dates, UUIDs and one-click clipboard encoders.", symbol: "curlybraces", tint: .indigo, category: .tools, sizes: [.small, .medium, .large], defaultSize: .medium)
        case .onThisDay:
            return .init(title: "On This Day", summary: "Something that happened on today's date, from Wikipedia.", symbol: "clock.arrow.circlepath", tint: .brown, category: .media, sizes: [.small, .medium, .wide, .large, .tall], defaultSize: .medium)
        case .deviceBatteries:
            return .init(title: "Device Batteries", summary: "Battery rings for your Mac, AirPods, mouse and keyboard.", symbol: "battery.75percent", tint: .green, category: .system, sizes: [.small, .medium, .large])

        // Version 5
        case .slateToday:
            return .init(title: "Slate Today", summary: "The to-dos in today's Slate note. Click one to tick it off.", symbol: "square.stack.3d.up.fill", tint: Slate.stone, category: .web, sizes: [.small, .medium, .wide, .large, .portrait], defaultSize: .medium)
        case .slateStreak:
            return .init(title: "Slate Streak", summary: "Your daily-note streak and a year of the days you wrote.", symbol: "square.stack.3d.up.fill", tint: Slate.stone, category: .web, sizes: [.small, .medium, .wide, .large], defaultSize: .medium)
        case .ciRuns:
            return .init(title: "GitHub Actions", summary: "The latest CI run for each of your repos: passing, failing or running.", symbol: "checkmark.seal.fill", tint: .green, category: .web, sizes: [.small, .medium, .large, .tall], defaultSize: .medium)
        case .claudeBudget:
            return .init(title: "Claude Sessions", summary: "Click it each time you start a 5-hour Claude Code window. Spreads your week into a daily share.", symbol: "gauge.with.needle.fill", tint: Palette.claude, category: .productivity, sizes: smallMedium, defaultSize: .medium)
        }
    }

    /// Widgets drawn in Slate's colours with its logo.
    var isSlate: Bool { self == .cairn || self == .slateToday || self == .slateStreak }

    var title: String { info.title }
    var summary: String { info.summary }
    var symbol: String { info.symbol }
    var tint: Color { info.tint }
    var category: WidgetCategory { info.category }
    var sizes: [WidgetSize] { info.sizes }
    var defaultSize: WidgetSize { info.defaultSize }

    /// Widgets that animate continuously (they pause automatically when covered).
    var isAnimated: Bool {
        switch self {
        case .crabPet, .lifeGame, .breathe, .water:
            return true
        default:
            return false
        }
    }
}

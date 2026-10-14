import SwiftUI
import AppKit

// MARK: - Flip clock

enum FlipClockKeys {
    static let use24Hour = ConfigKey("use24Hour", false)
    static let showSeconds = ConfigKey("showSeconds", false)
}

private struct FlipCard: View {
    let text: String
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
            Text(text)
                .font(.system(size: size * 0.78, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(white: 0.94))
                .minimumScaleFactor(0.5)
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .frame(height: max(1.5, size * 0.025))
            HStack {
                Circle().fill(Color.black.opacity(0.6)).frame(width: size * 0.06)
                Spacer()
                Circle().fill(Color.black.opacity(0.6)).frame(width: size * 0.06)
            }
            .padding(.horizontal, -size * 0.02)
        }
        .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
    }
}

struct FlipClockWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        let seconds = model[FlipClockKeys.showSeconds]
        Ticking(everySecond: seconds) { date in
            let use24 = model[FlipClockKeys.use24Hour]
            let hours = DateFormats.string(date, format: use24 ? "HH" : "hh")
            let minutes = DateFormats.string(date, format: "mm")
            let secs = DateFormats.string(date, format: "ss")
            let small = model.family == .small
            let cardSize: CGFloat = small ? 62 : (seconds ? 88 : 112)
            VStack(spacing: small ? 8 : 6) {
                if small {
                    HStack(spacing: 8) {
                        FlipCard(text: hours, size: cardSize).frame(width: cardSize, height: cardSize * 1.15)
                        FlipCard(text: minutes, size: cardSize).frame(width: cardSize, height: cardSize * 1.15)
                    }
                } else {
                    HStack(spacing: 10) {
                        FlipCard(text: hours, size: cardSize).frame(width: cardSize, height: cardSize * 1.05)
                        FlipCard(text: minutes, size: cardSize).frame(width: cardSize, height: cardSize * 1.05)
                        if seconds {
                            FlipCard(text: secs, size: cardSize).frame(width: cardSize, height: cardSize * 1.05)
                        }
                    }
                }
                Text(use24 ? DateFormats.string(date, template: "EEEMMMd") : DateFormats.meridiem(date) + " · " + DateFormats.string(date, template: "EEEMMMd"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Word clock

struct WordClockWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetStyle) private var style

    private static let rows = [
        "ITLISASAMPM", "ACQUARTERDC", "TWENTYFIVEX", "HALFSTENFTO", "PASTERUNINE",
        "ONESIXTHREE", "FOURFIVETWO", "EIGHTELEVEN", "SEVENTWELVE", "TENSEOCLOCK",
    ]

    /// (row, first column, length)
    private typealias Word = (Int, Int, Int)
    private static let it: Word = (0, 0, 2), isWord: Word = (0, 3, 2)
    private static let a: Word = (1, 0, 1), quarter: Word = (1, 2, 7)
    private static let twenty: Word = (2, 0, 6), fiveMinutes: Word = (2, 6, 4)
    private static let half: Word = (3, 0, 4), tenMinutes: Word = (3, 5, 3), to: Word = (3, 9, 2)
    private static let past: Word = (4, 0, 4)
    private static let oclock: Word = (9, 5, 6)
    private static let hours: [Word] = [
        (8, 5, 6), (5, 0, 3), (6, 8, 3), (5, 6, 5), (6, 0, 4), (6, 4, 4),
        (5, 3, 3), (8, 0, 5), (7, 0, 5), (4, 7, 4), (9, 0, 3), (7, 5, 6),
    ] // twelve, one, two … eleven

    private func litCells(_ date: Date) -> (Set<Int>, Int) {
        let calendar = Calendar.current
        var hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let block = minute / 5 * 5
        var words: [Word] = [Self.it, Self.isWord]
        switch block {
        case 0: words.append(Self.oclock)
        case 5: words += [Self.fiveMinutes, Self.past]
        case 10: words += [Self.tenMinutes, Self.past]
        case 15: words += [Self.a, Self.quarter, Self.past]
        case 20: words += [Self.twenty, Self.past]
        case 25: words += [Self.twenty, Self.fiveMinutes, Self.past]
        case 30: words += [Self.half, Self.past]
        case 35: words += [Self.twenty, Self.fiveMinutes, Self.to]
        case 40: words += [Self.twenty, Self.to]
        case 45: words += [Self.a, Self.quarter, Self.to]
        case 50: words += [Self.tenMinutes, Self.to]
        default: words += [Self.fiveMinutes, Self.to]
        }
        if block >= 35 { hour += 1 }
        words.append(Self.hours[hour % 12])
        var cells = Set<Int>()
        for (row, column, length) in words {
            for offset in 0..<length { cells.insert(row * 11 + column + offset) }
        }
        return (cells, minute % 5)
    }

    private static let hourNames = ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven"]

    /// The same time in plain words, for the medium layout.
    private func phrase(_ date: Date) -> String {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date) / 5 * 5
        let hour = calendar.component(.hour, from: date) + (minute >= 35 ? 1 : 0)
        let name = Self.hourNames[hour % 12]
        switch minute {
        case 0: return "It's \(name) o'clock"
        case 15: return "It's quarter past \(name)"
        case 30: return "It's half past \(name)"
        case 45: return "It's quarter to \(name)"
        case ..<30: return "It's \(Self.minuteWords[minute] ?? "") past \(name)"
        default: return "It's \(Self.minuteWords[60 - minute] ?? "") to \(name)"
        }
    }

    private static let minuteWords = [5: "five", 10: "ten", 20: "twenty", 25: "twenty-five"]

    var body: some View {
        Ticking(everySecond: false) { date in
            if model.family == .medium {
                HStack(spacing: 18) {
                    grid(date, fontSize: 10, spacing: 2)
                        .aspectRatio(1, contentMode: .fit)
                    Text(phrase(date))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(style.tone(accent))
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .widgetPadding(18)
            } else {
                grid(date, fontSize: model.family == .small ? 10.5 : 20, spacing: model.family == .small ? 2 : 6)
                    .widgetPadding(model.family == .small ? 14 : 26)
            }
        }
    }

    private func grid(_ date: Date, fontSize: CGFloat, spacing: CGFloat) -> some View {
            let state = litCells(date)
            let lit = state.0
            let extra = state.1
            let tone = style.tone(accent)
            return ZStack {
                VStack(spacing: spacing) {
                    ForEach(0..<10, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(Array(Self.rows[row].enumerated()), id: \.offset) { column, letter in
                                Text(String(letter))
                                    .font(.system(size: fontSize, weight: lit.contains(row * 11 + column) ? .bold : .regular, design: .monospaced))
                                    .foregroundStyle(lit.contains(row * 11 + column) ? AnyShapeStyle(tone) : AnyShapeStyle(Color.primary.opacity(0.13)))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                // Minute dots in the corners (1–4 minutes past the five).
                VStack {
                    HStack { dot(extra >= 1, tone); Spacer(); dot(extra >= 2, tone) }
                    Spacer()
                    HStack { dot(extra >= 4, tone); Spacer(); dot(extra >= 3, tone) }
                }
                .padding(-6)
            }
    }

    private func dot(_ on: Bool, _ tone: Color) -> some View {
        Circle().fill(on ? tone : Color.primary.opacity(0.12)).frame(width: 4, height: 4)
    }
}

// MARK: - Binary clock

struct BinaryClockWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    var body: some View {
        Ticking(everySecond: true) { date in
            let calendar = Calendar.current
            let parts = [calendar.component(.hour, from: date), calendar.component(.minute, from: date), calendar.component(.second, from: date)]
            let digits = parts.flatMap { [$0 / 10, $0 % 10] }
            let maxBits = [2, 4, 3, 4, 3, 4]
            let dot: CGFloat = model.family == .small ? 14 : 22
            VStack(spacing: 8) {
                HStack(alignment: .bottom, spacing: model.family == .small ? 6 : 14) {
                    ForEach(0..<6, id: \.self) { column in
                        VStack(spacing: 5) {
                            ForEach((0..<4).reversed(), id: \.self) { bit in
                                let used = bit < maxBits[column]
                                let on = (digits[column] >> bit) & 1 == 1
                                Circle()
                                    .fill(on ? style.tone(.green) : Color.primary.opacity(used ? 0.12 : 0))
                                    .frame(width: dot, height: dot)
                                    .shadow(color: on ? Color.green.opacity(0.6) : .clear, radius: 4)
                            }
                            Text("\(digits[column])")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if column == 1 || column == 3 { Color.clear.frame(width: model.family == .small ? 0 : 6) }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Lava lamp

enum LavaKeys {
    static let theme = ConfigKey("theme", LavaTheme.sunset)
}

enum LavaTheme: String, ConfigOption {
    case sunset, ocean, lime, grape, cherry

    var label: String { rawValue.capitalized }

    var colors: (blob: Color, top: Color, bottom: Color) {
        switch self {
        case .sunset: return (Color(hex: 0xFF7A3D), Color(hex: 0x2B0F3A), Color(hex: 0x6B1D3A))
        case .ocean: return (Color(hex: 0x3DD6FF), Color(hex: 0x071A3A), Color(hex: 0x0E3D6B))
        case .lime: return (Color(hex: 0xB6FF3D), Color(hex: 0x0F2B12), Color(hex: 0x1D5A2A))
        case .grape: return (Color(hex: 0xD27BFF), Color(hex: 0x1A0B2E), Color(hex: 0x3E1A6B))
        case .cherry: return (Color(hex: 0xFF3D6E), Color(hex: 0x2E0B14), Color(hex: 0x5A1428))
        }
    }
}

struct LavaLampWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        let theme = model[LavaKeys.theme].colors
        Animated(fps: 15) { date in
            let time = date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.alphaThreshold(min: 0.45, color: theme.blob))
                context.addFilter(.blur(radius: min(size.width, size.height) * 0.07))
                context.drawLayer { layer in
                    for index in 0..<7 {
                        let speed = 0.05 + seededRandom(index) * 0.08
                        let phase = seededRandom(index + 40) * .pi * 2
                        let x = size.width * (0.2 + 0.6 * (0.5 + 0.5 * sin(time * speed * 0.7 + phase)))
                        let y = size.height * (0.5 + 0.45 * sin(time * speed + phase * 1.3))
                        let radius = min(size.width, size.height) * (0.1 + seededRandom(index + 80) * 0.1)
                        layer.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                   with: .color(.white))
                    }
                    // A pool at the bottom and top, like a real lamp.
                    layer.fill(Path(ellipseIn: CGRect(x: -size.width * 0.1, y: size.height * 0.88, width: size.width * 1.2, height: size.height * 0.3)), with: .color(.white))
                }
            }
        }
        .widgetBackground(.gradient(theme.top, theme.bottom))
    }
}

// MARK: - Aquarium

struct AquariumWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        Animated(fps: 15) { date in
            let time = date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                // Sand.
                var sand = Path()
                sand.move(to: CGPoint(x: 0, y: size.height))
                for step in 0...20 {
                    let x = size.width * CGFloat(step) / 20
                    sand.addLine(to: CGPoint(x: x, y: size.height - 14 - 4 * CGFloat(sin(Double(step) * 0.9))))
                }
                sand.addLine(to: CGPoint(x: size.width, y: size.height))
                context.fill(sand, with: .color(Color(hex: 0xE8D3A0)))

                // Seaweed swaying.
                for index in 0..<5 {
                    let baseX = size.width * CGFloat(0.08 + 0.21 * Double(index) + seededRandom(index) * 0.06)
                    let height = size.height * CGFloat(0.25 + seededRandom(index + 10) * 0.25)
                    var weed = Path()
                    weed.move(to: CGPoint(x: baseX, y: size.height - 10))
                    for step in 1...10 {
                        let t = CGFloat(step) / 10
                        let sway = CGFloat(sin(time * 1.2 + Double(index) + Double(t) * 2.5)) * 5 * t
                        weed.addLine(to: CGPoint(x: baseX + sway, y: size.height - 10 - height * t))
                    }
                    context.stroke(weed, with: .color(Color(hex: 0x2E9E5B)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }

                // Bubbles.
                for index in 0..<10 {
                    let speed = 18 + seededRandom(index + 20) * 20
                    let travel = Double(size.height) + 20
                    let y = Double(size.height) - (time * speed + seededRandom(index + 30) * travel).truncatingRemainder(dividingBy: travel)
                    let x = Double(size.width) * seededRandom(index + 50) + sin(time * 2 + Double(index)) * 3
                    let radius = 2 + seededRandom(index + 60) * 3
                    context.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                   with: .color(.white.opacity(0.6)), lineWidth: 1)
                }

                // Fish.
                let fishes = ["🐠", "🐟", "🐡", "🐠", "🐟"]
                let count = size.width > 300 ? 5 : 3
                for index in 0..<count {
                    let speed = 0.04 + seededRandom(index + 70) * 0.05
                    let phase = (time * speed + seededRandom(index + 90)).truncatingRemainder(dividingBy: 2)
                    let goingRight = phase < 1
                    let progress = goingRight ? phase : 2 - phase
                    let x = 18 + (Double(size.width) - 36) * progress
                    let y = Double(size.height) * (0.2 + 0.5 * seededRandom(index + 100)) + sin(time * 1.5 + Double(index)) * 6
                    let fontSize = 20 + seededRandom(index + 110) * 10
                    var fishContext = context
                    fishContext.translateBy(x: x, y: y)
                    // Apple's fish emoji face left; mirror them when swimming right.
                    if goingRight { fishContext.scaleBy(x: -1, y: 1) }
                    fishContext.draw(Text(fishes[index]).font(.system(size: fontSize)), at: .zero)
                }
            }
        }
        .widgetBackground(.gradient(Color(hex: 0x3BB7E8), Color(hex: 0x0B5FA5)))
    }
}

// MARK: - Digital rain

struct DigitalRainWidget: View {
    @ObservedObject var model: WidgetModel
    private static let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789")

    var body: some View {
        Animated(fps: 12) { date in
            let time = date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let cell: CGFloat = 12
                let columns = Int(size.width / cell)
                let rows = Int(size.height / cell) + 1
                let frame = Int(time * 12)
                for column in 0..<columns {
                    let speed = 6 + seededRandom(column) * 10
                    let length = 6 + Int(seededRandom(column + 500) * 12)
                    let span = Double(rows + length)
                    let head = Int((time * speed + seededRandom(column + 900) * span).truncatingRemainder(dividingBy: span))
                    for offset in 0..<length {
                        let row = head - offset
                        guard row >= 0, row < rows else { continue }
                        let glyph = Self.glyphs[Int(seededRandom(column * 131 + row * 7 + (offset == 0 ? frame : frame / 6)) * Double(Self.glyphs.count)) % Self.glyphs.count]
                        let fade = 1 - Double(offset) / Double(length)
                        let color = offset == 0 ? Color(hex: 0xD8FFD8) : Color(hex: 0x00FF6A).opacity(fade * 0.9)
                        context.draw(Text(String(glyph)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(color),
                                     at: CGPoint(x: CGFloat(column) * cell + cell / 2, y: CGFloat(row) * cell + cell / 2))
                    }
                }
            }
        }
        .widgetBackground(.color(Color(hex: 0x020A04)))
    }
}

// MARK: - Night sky

struct NightSkyWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        Animated(fps: 10) { date in
            let time = date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let starCount = Int(size.width * size.height / 450)
                for index in 0..<starCount {
                    let x = Double(size.width) * seededRandom(index)
                    let y = Double(size.height) * 0.8 * seededRandom(index + 7_000)
                    let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * (0.6 + seededRandom(index + 3_000) * 2) + seededRandom(index + 5_000) * 6))
                    let radius = 0.5 + seededRandom(index + 9_000) * 1.1
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(.white.opacity(twinkle)))
                }
                // Moon.
                let moon = CGRect(x: size.width * 0.75, y: size.height * 0.12, width: 26, height: 26)
                context.fill(Path(ellipseIn: moon.insetBy(dx: -8, dy: -8)), with: .color(.white.opacity(0.06)))
                context.fill(Path(ellipseIn: moon), with: .color(Color(hex: 0xF4F1DE)))
                context.fill(Path(ellipseIn: moon.offsetBy(dx: 8, dy: -4)), with: .color(Color(hex: 0x141B3D)))
                // A shooting star every ~9 seconds.
                let cycle = time.truncatingRemainder(dividingBy: 9)
                if cycle < 1.1 {
                    let seed = Int(time / 9)
                    let startX = Double(size.width) * (0.1 + seededRandom(seed) * 0.5)
                    let startY = Double(size.height) * 0.1 * seededRandom(seed + 1)
                    let progress = cycle / 1.1
                    let head = CGPoint(x: startX + progress * 110, y: startY + progress * 55)
                    var trail = Path()
                    trail.move(to: head)
                    trail.addLine(to: CGPoint(x: head.x - 36, y: head.y - 18))
                    context.stroke(trail, with: .linearGradient(Gradient(colors: [.white.opacity(0.9 * (1 - progress)), .clear]),
                                                               startPoint: head, endPoint: CGPoint(x: head.x - 36, y: head.y - 18)),
                                   lineWidth: 1.6)
                }
                // Mountains.
                var hills = Path()
                hills.move(to: CGPoint(x: 0, y: size.height))
                for step in 0...12 {
                    let x = size.width * CGFloat(step) / 12
                    let peak = CGFloat(seededRandom(step + 400)) * size.height * 0.22
                    hills.addLine(to: CGPoint(x: x, y: size.height * 0.86 - peak))
                }
                hills.addLine(to: CGPoint(x: size.width, y: size.height))
                context.fill(hills, with: .color(Color(hex: 0x070A1A)))
            }
        }
        .widgetBackground(.gradient(Color(hex: 0x0A0F2C), Color(hex: 0x2B2F6B)))
    }
}

// MARK: - Game of Life

final class LifeBoard: ObservableObject {
    @Published private(set) var cells: [Bool] = []
    private(set) var columns = 0
    private(set) var rows = 0
    private var generation = 0
    private var history: [Int] = []

    func ensure(columns: Int, rows: Int) {
        guard columns != self.columns || rows != self.rows else { return }
        self.columns = columns
        self.rows = rows
        seed()
    }

    func seed() {
        cells = (0..<(columns * rows)).map { _ in Double.random(in: 0..<1) < 0.28 }
        generation = 0
        history = []
    }

    func step() {
        guard columns > 0, rows > 0 else { return }
        var next = cells
        for row in 0..<rows {
            for column in 0..<columns {
                var neighbors = 0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let x = (column + dx + columns) % columns
                        let y = (row + dy + rows) % rows
                        if cells[y * columns + x] { neighbors += 1 }
                    }
                }
                let alive = cells[row * columns + column]
                next[row * columns + column] = alive ? (neighbors == 2 || neighbors == 3) : neighbors == 3
            }
        }
        cells = next
        generation += 1
        // Reseed when the board dies out or gets stuck in a loop.
        let signature = next.enumerated().reduce(0) { $1.element ? $0 &+ ($1.offset &* 2_654_435_761) : $0 }
        history.append(signature)
        if history.count > 12 { history.removeFirst() }
        let living = next.filter { $0 }.count
        if living < 4 || generation > 500 || Set(history).count < history.count / 2 {
            seed()
        }
    }
}

struct LifeGameWidget: View {
    @ObservedObject var model: WidgetModel
    @StateObject private var board = LifeBoard()
    @Environment(\.widgetIsVisible) private var visible
    @Environment(\.widgetStyle) private var style
    private static let ticker = Timer.publish(every: 0.25, tolerance: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        let cell: CGFloat = 7
        let size = model.size.dimensions
        let columns = Int((size.width - 16) / cell)
        let rows = Int((size.height - 16) / cell)
        let tone = style.tone(.mint)
        Canvas { context, _ in
            for (index, alive) in board.cells.enumerated() where alive {
                let x = CGFloat(index % max(board.columns, 1)) * cell
                let y = CGFloat(index / max(board.columns, 1)) * cell
                context.fill(Path(roundedRect: CGRect(x: x + 0.5, y: y + 0.5, width: cell - 1, height: cell - 1), cornerRadius: 1.5),
                             with: .color(tone))
            }
        }
        .frame(width: CGFloat(columns) * cell, height: CGFloat(rows) * cell)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { board.seed() }
        .onAppear { board.ensure(columns: columns, rows: rows) }
        .onChange(of: model.size) { _, _ in board.ensure(columns: columns, rows: rows) }
        .onReceive(Self.ticker) { _ in
            if visible {
                board.ensure(columns: columns, rows: rows)
                board.step()
            }
        }
        .help("Click to reseed")
    }
}

// MARK: - Bouncing text

enum BounceKeys {
    static let text = ConfigKey("text", "DVD")
}

struct BounceWidget: View {
    @ObservedObject var model: WidgetModel
    private static let colors: [Color] = [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .pink]

    var body: some View {
        let label = model[BounceKeys.text]
        GeometryReader { geometry in
            Animated(fps: 30) { date in
                let time = date.timeIntervalSinceReferenceDate
                let textWidth = CGFloat(max(2, label.count)) * 15 + 20
                let textHeight: CGFloat = 32
                let travelX = max(1, Double(geometry.size.width - textWidth))
                let travelY = max(1, Double(geometry.size.height - textHeight))
                let speed = 45.0
                let positionX = (time * speed).truncatingRemainder(dividingBy: travelX * 2)
                let positionY = (time * speed * 0.73).truncatingRemainder(dividingBy: travelY * 2)
                let x = positionX < travelX ? positionX : travelX * 2 - positionX
                let y = positionY < travelY ? positionY : travelY * 2 - positionY
                let bounces = Int(time * speed / travelX) + Int(time * speed * 0.73 / travelY)
                Text(label)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .italic()
                    .foregroundStyle(Self.colors[bounces % Self.colors.count])
                    .lineLimit(1)
                    .frame(width: textWidth, height: textHeight)
                    .position(x: CGFloat(x) + textWidth / 2, y: CGFloat(y) + textHeight / 2)
            }
        }
        .widgetBackground(.color(Color(white: 0.04)))
    }
}

// MARK: - Mood gradient

enum MoodKeys {
    static let palette = ConfigKey("palette", MoodPalette.sunset)
}

enum MoodPalette: String, ConfigOption {
    case sunset, ocean, forest, candy, aurora, mono

    var label: String { rawValue.capitalized }

    var colors: [Color] {
        switch self {
        case .sunset: return [Color(hex: 0xFF5E62), Color(hex: 0xFF9966), Color(hex: 0xFFC371), Color(hex: 0xC33764)]
        case .ocean: return [Color(hex: 0x00C9FF), Color(hex: 0x1E3C72), Color(hex: 0x92FE9D), Color(hex: 0x2A5298)]
        case .forest: return [Color(hex: 0x134E5E), Color(hex: 0x71B280), Color(hex: 0xC6EA8D), Color(hex: 0x2C5F2D)]
        case .candy: return [Color(hex: 0xF9A8D4), Color(hex: 0xA78BFA), Color(hex: 0x67E8F9), Color(hex: 0xFDE68A)]
        case .aurora: return [Color(hex: 0x00F5A0), Color(hex: 0x00D9F5), Color(hex: 0x7F00FF), Color(hex: 0x0B132B)]
        case .mono: return [Color(white: 0.85), Color(white: 0.45), Color(white: 0.65), Color(white: 0.2)]
        }
    }
}

struct MoodGradientWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        let colors = model[MoodKeys.palette].colors
        Animated(fps: 10) { date in
            let time = date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colors[3]))
                context.addFilter(.blur(radius: min(size.width, size.height) * 0.28))
                for index in 0..<3 {
                    let speed = 0.05 + Double(index) * 0.02
                    let x = Double(size.width) * (0.5 + 0.45 * sin(time * speed + Double(index) * 2.1))
                    let y = Double(size.height) * (0.5 + 0.45 * cos(time * speed * 1.3 + Double(index) * 1.7))
                    let radius = Double(max(size.width, size.height)) * 0.45
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(colors[index]))
                }
            }
        }
        .widgetBackground(.edgeToEdge)
    }
}

// MARK: - Color palette

enum PaletteKeys {
    static let seed = ConfigKey("seed", 7)
}

struct PaletteWidget: View {
    @ObservedObject var model: WidgetModel
    @State private var copied: Int?

    private func colors(seed: Int) -> [NSColor] {
        let base = seededRandom(seed)
        let scheme = Int(seededRandom(seed + 1) * 3)
        return (0..<5).map { index in
            let hue: Double
            switch scheme {
            case 0: hue = base + Double(index) * 0.06 // analogous
            case 1: hue = base + (index % 2 == 0 ? 0 : 0.5) + Double(index) * 0.02 // complementary
            default: hue = base + Double(index) * 0.2 // spread
            }
            let saturation = 0.45 + seededRandom(seed * 13 + index) * 0.45
            let brightness = 0.55 + seededRandom(seed * 17 + index) * 0.4
            return NSColor(hue: CGFloat(hue.truncatingRemainder(dividingBy: 1)), saturation: CGFloat(saturation), brightness: CGFloat(brightness), alpha: 1)
        }
    }

    private func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }

    var body: some View {
        let seed = model[PaletteKeys.seed]
        let swatches = colors(seed: seed)
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(swatches.enumerated()), id: \.offset) { index, color in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(hex(color), forType: .string)
                        copied = index
                    } label: {
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: color))
                                .overlay {
                                    if copied == index {
                                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white)
                                    }
                                }
                            if model.family != .small {
                                Text(hex(color)).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(WidgetButtonStyle())
                    .help("Copy \(hex(color))")
                }
            }
            HStack {
                Text(copied == nil ? "Click a color to copy" : "Copied!")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.config[PaletteKeys.seed] = seed + 1
                    copied = nil
                } label: {
                    Label("New", systemImage: "shuffle")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(WidgetButtonStyle())
            }
        }
        .widgetPadding()
    }
}

// MARK: - Dice & coin

struct DiceWidget: View {
    @ObservedObject var model: WidgetModel
    @State private var die = 6
    @State private var coin = true
    @State private var spins = 0.0
    @State private var flips = 0.0

    private func pips(_ value: Int) -> [(CGFloat, CGFloat)] {
        let low: CGFloat = 0.25, mid: CGFloat = 0.5, high: CGFloat = 0.75
        switch value {
        case 1: return [(mid, mid)]
        case 2: return [(low, low), (high, high)]
        case 3: return [(low, low), (mid, mid), (high, high)]
        case 4: return [(low, low), (high, low), (low, high), (high, high)]
        case 5: return [(low, low), (high, low), (mid, mid), (low, high), (high, high)]
        default: return [(low, low), (high, low), (low, mid), (high, mid), (low, high), (high, high)]
        }
    }

    private var dieView: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                die = Int.random(in: 1...6)
                spins += 360
            }
        } label: {
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    ForEach(Array(pips(die).enumerated()), id: \.offset) { _, pip in
                        Circle()
                            .fill(die == 1 ? Color.red : Color(white: 0.12))
                            .frame(width: side * 0.17, height: side * 0.17)
                            .position(x: side * pip.0, y: side * pip.1)
                    }
                }
                .frame(width: side, height: side)
                .rotationEffect(.degrees(spins))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .buttonStyle(.plain)
        .help("Roll the die")
    }

    private var coinView: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.5)) {
                coin = Bool.random()
                flips += 540
            }
        } label: {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(hex: 0xF7D774), Color(hex: 0xC9962B)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Circle().strokeBorder(Color(hex: 0xA77A1E), lineWidth: 3).padding(5)
                Text(coin ? "H" : "T")
                    .font(.system(size: 34, weight: .heavy, design: .serif))
                    .foregroundStyle(Color(hex: 0x7A5512))
            }
            .rotation3DEffect(.degrees(flips), axis: (x: 0, y: 1, z: 0))
        }
        .buttonStyle(.plain)
        .help("Flip the coin")
    }

    var body: some View {
        HStack(spacing: 18) {
            dieView.frame(width: 96, height: 96)
            if model.family != .small {
                coinView.frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rolled \(die)").font(.system(size: 13, weight: .semibold))
                    Text(coin ? "Heads" : "Tails").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Text("Click to roll or flip").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pixel plant

enum PlantKeys {
    static let lastWatered = ConfigKey("lastWatered", "")
    static let streak = ConfigKey("streak", 0)
    static let name = ConfigKey("name", "Sprout")
}

struct PlantWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context

    private func daysSinceWatered(_ now: Date) -> Int? {
        let last = model[PlantKeys.lastWatered]
        guard !last.isEmpty, let date = DateFormats.formatter(format: "yyyy-MM-dd").date(from: last) else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
    }

    private func water(_ now: Date) {
        let since = daysSinceWatered(now)
        guard since != 0 else { return }
        let streak = since == 1 ? model[PlantKeys.streak] + 1 : 1
        model.config[PlantKeys.streak] = streak
        model.config[PlantKeys.lastWatered] = DateFormats.string(now, format: "yyyy-MM-dd")
    }

    var body: some View {
        Ticking(everySecond: false) { now in
            let since = context == .gallery ? 0 : daysSinceWatered(now)
            let streak = context == .gallery ? 14 : model[PlantKeys.streak]
            let wilting = (since ?? 0) >= 2
            let stage = min(5, streak == 0 ? 0 : (streak < 3 ? 1 : (streak < 6 ? 2 : (streak < 10 ? 3 : (streak < 20 ? 4 : 5)))))
            VStack(spacing: 6) {
                PixelPlant(stage: stage, wilting: wilting)
                    .frame(maxHeight: .infinity)
                Text(model[PlantKeys.name])
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                Text(wilting ? "Thirsty! 🥀" : (since == 0 ? "Watered today · \(streak) day streak" : "Needs water today"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(wilting ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button {
                    water(now)
                } label: {
                    Label(since == 0 ? "Watered" : "Water", systemImage: "drop.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.blue.opacity(since == 0 ? 0.12 : 0.85)))
                        .foregroundStyle(since == 0 ? Color.blue : Color.white)
                }
                .buttonStyle(WidgetButtonStyle())
                .disabled(since == 0)
            }
            .widgetPadding(12)
        }
    }
}

/// A plant drawn in chunky pixels; grows taller and flowers as the streak grows.
struct PixelPlant: View {
    let stage: Int
    let wilting: Bool

    var body: some View {
        let leaf = wilting ? Color(hex: 0x9C8A3E) : Color(hex: 0x3DBB5A)
        let stem = wilting ? Color(hex: 0x7A6A2E) : Color(hex: 0x2E8B45)
        let level = stage
        let droop = wilting
        return Canvas { context, size in
            let pixel = min(size.width / 16, size.height / 20)
            let originX = (size.width - pixel * 16) / 2
            let originY = size.height - pixel * 20
            func dot(_ x: Int, _ y: Int, _ color: Color) {
                context.fill(Path(CGRect(x: originX + CGFloat(x) * pixel, y: originY + CGFloat(y) * pixel, width: pixel + 0.4, height: pixel + 0.4)),
                             with: .color(color))
            }
            // Pot.
            let pot = Color(hex: 0xC8643B), potDark = Color(hex: 0x9E4A2B)
            for x in 4...11 { dot(x, 15, potDark) }
            for y in 16...19 { for x in (5 + (y - 16) / 2)...(10 - (y - 16) / 2) { dot(x, y, pot) } }
            for x in 5...10 { dot(x, 15, Color(hex: 0x5A3A22)) }
            guard level > 0 else {
                dot(7, 14, Color(hex: 0x6B4A2E)); dot(8, 14, Color(hex: 0x6B4A2E))
                return
            }
            // Stem grows with the stage.
            let height = [0, 2, 4, 6, 8, 10][level]
            for step in 0..<height {
                let lean = droop && step > height / 2 ? 1 : 0
                dot(8 + lean, 14 - step, stem)
            }
            // Leaves alternate up the stem.
            for pair in 0..<(level + 1) where pair * 2 + 1 < height {
                let y = 13 - pair * 2
                let sag = droop ? 1 : 0
                dot(6, y + sag, leaf); dot(7, y, leaf)
                dot(9, y - 1 + sag, leaf); dot(10, y - 1 + sag, leaf)
            }
            // A flower on top at the last stage.
            if level == 5 && !droop {
                let top = 14 - height
                let petal = Color(hex: 0xFF6FA8)
                dot(8, top - 1, petal); dot(7, top, petal); dot(9, top, petal); dot(8, top + 1, petal)
                dot(8, top, Color(hex: 0xFFD23F))
            }
        }
    }
}

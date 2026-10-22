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

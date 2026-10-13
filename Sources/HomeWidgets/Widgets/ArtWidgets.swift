import SwiftUI

// Aesthetic widgets that make the desktop look good: generative art, a living
// mesh gradient, waves, aurora, a spirograph, orbits, big type and time rings.

enum ArtKeys {
    static let style = ConfigKey("artStyle", "")
    static let palette = ConfigKey("artPalette", "sonoma")
    static let seed = ConfigKey("artSeed", 7)
    static let animate = ConfigKey("artAnimate", true)
}

/// One widget type per look in the gallery, all drawn by `AbstractArt`.
struct ArtSceneWidget: View {
    @ObservedObject var model: WidgetModel
    let defaultStyle: ArtStyle
    var defaultPalette = "sonoma"

    var body: some View {
        let style = ArtStyle(rawValue: model[ArtKeys.style]) ?? defaultStyle
        let palette = ArtPalette.named(model.config.values[ArtKeys.palette.name] == nil ? defaultPalette : model[ArtKeys.palette])
        let seed = model[ArtKeys.seed]
        Group {
            if model[ArtKeys.animate] {
                Animated(fps: 12) { date in
                    AbstractArt(style: style, palette: palette, seed: seed, time: date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
                }
            } else {
                AbstractArt(style: style, palette: palette, seed: seed)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.config[ArtKeys.seed] = Int.random(in: 1...999_999) }
        .help("Click for a new design")
        .widgetBackground(.edgeToEdge)
    }
}

// MARK: - Mesh gradient

struct MeshGradientWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        let palette = ArtPalette.named(model[ArtKeys.palette]).swiftUI
        Animated(fps: 20) { date in
            let t = date.timeIntervalSinceReferenceDate
            if #available(macOS 15.0, *) {
                MeshGradient(width: 3, height: 3, points: Self.points(t), colors: [
                    palette[0], palette[2], palette[1],
                    palette[3], palette[4], palette[2],
                    palette[1], palette[5], palette[3],
                ])
            } else {
                AbstractArt(style: .blobs, palette: ArtPalette.named(model[ArtKeys.palette]), seed: model[ArtKeys.seed], time: t)
            }
        }
        .widgetBackground(.edgeToEdge)
    }

    @available(macOS 15.0, *)
    static func points(_ t: Double) -> [SIMD2<Float>] {
        func wobble(_ base: Float, _ speed: Double, _ offset: Double) -> Float { base + Float(sin(t * speed + offset)) * 0.18 }
        return [
            [0, 0], [0.5, 0], [1, 0],
            [0, wobble(0.5, 0.31, 1)], [wobble(0.5, 0.27, 2), wobble(0.5, 0.33, 3)], [1, wobble(0.5, 0.29, 4)],
            [0, 1], [wobble(0.5, 0.23, 5), 1], [1, 1],
        ]
    }
}

// MARK: - Spirograph

struct SpirographWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        let seed = model[ArtKeys.seed]
        var random = ArtRandom(seed)
        let R = 1.0, r = random.range(0.2, 0.8), d = random.range(0.3, 1.0)
        let palette = ArtPalette.named(model[ArtKeys.palette])
        Animated(fps: 24) { date in
            let progress = (date.timeIntervalSinceReferenceDate / 14).truncatingRemainder(dividingBy: 1)
            Canvas { context, size in
                let scale = min(size.width, size.height) * 0.42 / (R - r + d)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let total = Double.pi * 2 * 12
                let steps = 900
                let shown = Int(Double(steps) * progress) + 2
                var previous: CGPoint?
                for i in 0..<shown {
                    let t = total * Double(i) / Double(steps)
                    let x = (R - r) * cos(t) + d * cos((R - r) / r * t)
                    let y = (R - r) * sin(t) - d * sin((R - r) / r * t)
                    let point = CGPoint(x: center.x + x * scale, y: center.y + y * scale)
                    if let previous {
                        var segment = Path()
                        segment.move(to: previous)
                        segment.addLine(to: point)
                        let color = palette.swiftUI[2 + (i / 60) % 4]
                        context.stroke(segment, with: .color(color.opacity(0.35 + 0.65 * Double(i) / Double(shown))), lineWidth: 1.3)
                    }
                    previous = point
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.config[ArtKeys.seed] = Int.random(in: 1...999_999) }
        .help("Click for a new pattern")
        .widgetBackground(.gradient(Color(hex: palette.colors[0]), Color(hex: palette.colors[1])))
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Big date

enum BigDateKeys {
    static let gradient = ConfigKey("gradient", true)
}

struct BigDateWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetAccent) private var accent

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let date = timeline.date
            let tone = style.tone(accent)
            let fill: AnyShapeStyle = model[BigDateKeys.gradient] && style != .tinted
                ? AnyShapeStyle(LinearGradient(colors: [tone, tone.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(tone)
            if model.family == .small {
                VStack(spacing: -6) {
                    Text(DateFormats.string(date, template: "EEEE").uppercased())
                        .font(.system(size: 12, weight: .heavy)).tracking(2).foregroundStyle(.secondary)
                    Text(DateFormats.string(date, format: "d"))
                        .font(.system(size: 92, weight: .black, design: .rounded))
                        .foregroundStyle(fill)
                        .fitLine(0.5)
                    Text(DateFormats.string(date, template: "MMMM").uppercased())
                        .font(.system(size: 12, weight: .heavy)).tracking(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    Text(DateFormats.string(date, format: "d"))
                        .font(.system(size: 104, weight: .black, design: .rounded))
                        .foregroundStyle(fill)
                        .fitLine(0.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DateFormats.string(date, template: "EEEE")).font(.system(size: 24, weight: .bold))
                        Text(DateFormats.string(date, template: "MMMMyyyy")).font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                        Text("Week \(Calendar.current.component(.weekOfYear, from: date)) · Day \(Calendar.current.ordinality(of: .day, in: .year, for: date) ?? 1)")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .widgetPadding(18)
            }
        }
    }
}

// MARK: - Time rings

struct TimeRingsWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    private static let rings: [(String, Calendar.Component, Color)] = [
        ("Day", .day, Color(hex: 0xFA114F)),
        ("Week", .weekOfYear, Color(hex: 0x92E82A)),
        ("Month", .month, Color(hex: 0x1EEAEF)),
        ("Year", .year, Color(hex: 0xFFD60A)),
    ]

    static func progress(_ component: Calendar.Component, at date: Date) -> Double {
        guard let interval = Calendar.current.dateInterval(of: component, for: date) else { return 0 }
        return date.timeIntervalSince(interval.start) / interval.duration
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let values = Self.rings.map { ($0.0, Self.progress($0.1, at: timeline.date), $0.2) }
            HStack(spacing: 14) {
                ZStack {
                    ForEach(values.indices, id: \.self) { index in
                        let inset = CGFloat(index) * 13
                        Circle().stroke(values[index].2.opacity(0.18), lineWidth: 10).padding(inset)
                        Circle()
                            .trim(from: 0, to: max(0.003, values[index].1))
                            .stroke(style == .tinted ? Color.white : values[index].2, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(inset)
                    }
                }
                .padding(5)
                .aspectRatio(1, contentMode: .fit)
                if model.family != .small {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(values.indices, id: \.self) { index in
                            HStack(spacing: 6) {
                                Circle().fill(values[index].2).frame(width: 7, height: 7)
                                Text(values[index].0).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(Int(values[index].1 * 100))%").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                            }
                        }
                    }
                }
            }
            .widgetPadding(12)
        }
    }
}

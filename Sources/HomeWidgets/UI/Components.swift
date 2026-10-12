import SwiftUI

/// Small colored icon + title row used at the top of most widgets.
struct WidgetHeader: View {
    let title: String
    let symbol: String
    let color: Color
    var trailing: String? = nil
    @Environment(\.widgetStyle) private var style

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(style.tone(color))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.tone(color))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

/// Circular progress ring, like the Batteries widget.
struct RingGauge<Center: View>: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 7
    @ViewBuilder var center: () -> Center
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let tone = style.tone(color)
        ZStack {
            Circle()
                .stroke(tone.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, value)))
                .stroke(tone, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center()
        }
        .padding(lineWidth / 2)
    }
}

extension RingGauge where Center == EmptyView {
    init(value: Double, color: Color, lineWidth: CGFloat = 7) {
        self.value = value
        self.color = color
        self.lineWidth = lineWidth
        self.center = { EmptyView() }
    }
}

/// A smooth area chart for recent history. Values are 0...1 unless `maxValue` is given.
struct Sparkline: View {
    let values: [Double]
    let color: Color
    var capacity = 60
    var maxValue: Double? = nil
    var lineWidth: CGFloat = 1.6
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let tone = style.tone(color)
        let ceiling = max(maxValue ?? 1, 0.000_001)
        let samples = values
        let slots = capacity
        Canvas { context, size in
            guard samples.count > 1 else { return }
            let step = size.width / CGFloat(max(slots - 1, 1))
            let startX = size.width - CGFloat(samples.count - 1) * step
            var line = Path()
            for (index, value) in samples.enumerated() {
                let normalized = CGFloat(min(max(value / ceiling, 0), 1))
                let point = CGPoint(x: startX + CGFloat(index) * step, y: size.height - normalized * (size.height - lineWidth) - lineWidth / 2)
                if index == 0 { line.move(to: point) } else { line.addLine(to: point) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: startX, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(Gradient(colors: [tone.opacity(0.38), tone.opacity(0.03)]),
                                                     startPoint: CGPoint(x: 0, y: 0),
                                                     endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(tone), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Horizontal capsule meter.
struct BarMeter: View {
    let value: Double
    let color: Color
    var height: CGFloat = 6
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let tone = style.tone(color)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(tone.opacity(0.2))
                Capsule()
                    .fill(tone)
                    .frame(width: max(height, geometry.size.width * CGFloat(min(max(value, 0), 1))))
            }
        }
        .frame(height: height)
    }
}

/// Several colored segments in one bar (used for memory breakdown).
struct SegmentedBar: View {
    struct Segment: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1.5) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(0, geometry.size.width * CGFloat(min(max(segment.value, 0), 1)) - 1.5))
                }
                Spacer(minLength: 0)
            }
            .background(Color.primary.opacity(0.12))
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

/// Vertical bars, e.g. one per CPU core.
struct ColumnBars: View {
    let values: [Double]
    let color: Color
    var spacing: CGFloat = 3
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let tone = style.tone(color)
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    ZStack(alignment: .bottom) {
                        Capsule().fill(tone.opacity(0.18))
                        Capsule()
                            .fill(tone)
                            .frame(height: max(3, geometry.size.height * CGFloat(min(max(value, 0), 1))))
                    }
                }
            }
        }
    }
}

/// Re-renders its content every second or every minute (cheap, uses TimelineView).
struct Ticking<Content: View>: View {
    var everySecond: Bool
    @ViewBuilder var content: (Date) -> Content

    private static var origin: Date { Date(timeIntervalSinceReferenceDate: 0) }

    var body: some View {
        if everySecond {
            TimelineView(.periodic(from: Self.origin, by: 1)) { timeline in
                content(timeline.date)
            }
        } else {
            TimelineView(.everyMinute) { timeline in
                content(timeline.date)
            }
        }
    }
}

/// Centered icon + message used for empty and permission states.
struct WidgetMessage: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A plain-looking button that highlights while pressed, used inside widgets.
struct WidgetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

/// Claude's sunburst mark, drawn as a shape.
struct ClaudeMark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let lengths: [CGFloat] = [1.0, 0.82, 0.94, 0.78, 1.0, 0.86, 0.92, 0.8, 0.98, 0.84, 0.9, 0.79]
        var path = Path()
        for (index, length) in lengths.enumerated() {
            let angle = Double(index) / Double(lengths.count) * 2 * .pi + 0.13
            let width = radius * 0.2
            let ray = Path(roundedRect: CGRect(x: -width / 2, y: -radius * length, width: width, height: radius * length),
                           cornerRadius: width / 2)
            let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
            path.addPath(ray, transform: transform)
        }
        return path
    }
}

/// Dot showing a Claude session's state.
struct StatusDot: View {
    let state: ClaudeMonitor.State

    var color: Color {
        switch state {
        case .working: return Palette.claude
        case .waiting: return .green
        case .idle: return .gray.opacity(0.5)
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: state == .idle ? 0 : 3))
    }
}

extension View {
    /// Applies the standard widget padding.
    func widgetPadding(_ amount: CGFloat = Layout.padding) -> some View {
        padding(amount)
    }

    /// Makes text never wrap and shrink a bit if needed.
    func fitLine(_ minimumScale: CGFloat = 0.6) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScale)
    }
}

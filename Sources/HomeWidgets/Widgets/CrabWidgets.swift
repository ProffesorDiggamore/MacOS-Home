import SwiftUI

/// The little blocky crab from the Claude Code logo, drawn as pixel art.
///
/// Pixel map (16 × 5, from the terminal logo `▐▛███▜▌ / ▝▜█████▛▘ / ▘▘ ▝▝`):
///   row 0: body top            row 3: body bottom
///   row 1: body with two eyes  row 4: four legs
///   row 2: body with claws
struct CrabSprite: View {
    enum Mood {
        case normal, blink, happy, sleeping, working
    }

    var mood: Mood = .normal
    /// Alternates the legs to make it look like it's walking.
    var step = 0
    var facingLeft = false
    var color: Color = Palette.claude

    private static let width = 18
    private static let height = 6

    private func cells() -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for column in 3...14 { result.append((column, 0)) }
        for column in 3...14 where column != 5 && column != 12 { result.append((column, 1)) }
        for column in 1...16 { result.append((column, 2)) }
        for column in 3...14 { result.append((column, 3)) }
        let legs = step % 2 == 0 ? [4, 6, 11, 13] : [5, 7, 10, 12]
        for column in legs { result.append((column, 4)) }
        return result
    }

    var body: some View {
        let shell = color
        let currentMood = mood
        let left = facingLeft
        let filled = cells()
        Canvas { context, size in
            let pixelWidth = size.width / CGFloat(Self.width)
            let pixelHeight = size.height / CGFloat(Self.height)
            func rect(_ column: Int, _ row: Int, inset: CGFloat = 0) -> CGRect {
                let x = left ? CGFloat(Self.width - 1 - column) : CGFloat(column)
                return CGRect(x: x * pixelWidth + inset, y: CGFloat(row) * pixelHeight + inset,
                              width: pixelWidth - inset * 2 + 0.5, height: pixelHeight - inset * 2 + 0.5)
            }
            for (column, row) in filled {
                context.fill(Path(rect(column, row)), with: .color(shell))
            }
            // Eyes: holes in row 1 normally; closed or happy eyes are drawn as lines in the body color.
            let dark = Color(white: 0.1)
            switch currentMood {
            case .normal, .working:
                context.fill(Path(rect(5, 1)), with: .color(dark))
                context.fill(Path(rect(12, 1)), with: .color(dark))
                if currentMood == .working {
                    // Little shine in the eyes while thinking.
                    let shine = CGRect(x: rect(5, 1).minX + pixelWidth * 0.55, y: rect(5, 1).minY + pixelHeight * 0.15,
                                       width: pixelWidth * 0.3, height: pixelHeight * 0.3)
                    context.fill(Path(shine), with: .color(.white.opacity(0.8)))
                    let shine2 = shine.offsetBy(dx: rect(12, 1).minX - rect(5, 1).minX, dy: 0)
                    context.fill(Path(shine2), with: .color(.white.opacity(0.8)))
                }
            case .blink, .sleeping:
                for column in [5, 12] {
                    let eye = rect(column, 1)
                    let lid = CGRect(x: eye.minX, y: eye.midY - pixelHeight * 0.12, width: eye.width, height: pixelHeight * 0.24)
                    context.fill(Path(rect(column, 1)), with: .color(shell))
                    context.fill(Path(lid), with: .color(dark))
                }
            case .happy:
                for column in [5, 12] {
                    let eye = rect(column, 1)
                    context.fill(Path(eye), with: .color(shell))
                    var arc = Path()
                    arc.move(to: CGPoint(x: eye.minX, y: eye.maxY - pixelHeight * 0.2))
                    arc.addLine(to: CGPoint(x: eye.midX, y: eye.minY + pixelHeight * 0.2))
                    arc.addLine(to: CGPoint(x: eye.maxX, y: eye.maxY - pixelHeight * 0.2))
                    context.stroke(arc, with: .color(dark), style: StrokeStyle(lineWidth: max(1.5, pixelWidth * 0.3), lineCap: .round, lineJoin: .round))
                }
            }
        }
        .aspectRatio(CGFloat(Self.width) / (CGFloat(Self.height) * 1.6), contentMode: .fit)
    }
}

// MARK: - Claude widget, mascot mode

/// The Claude Code widget shown as just the crab, reacting to what your sessions are doing.
struct ClaudeMascotView: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var claude = ClaudeMonitor.shared
    @Environment(\.widgetContext) private var context

    private var state: ClaudeMonitor.State {
        if context == .gallery { return .working }
        if claude.workingCount > 0 { return .working }
        if claude.waitingCount > 0 { return .waiting }
        return .idle
    }

    private var caption: String {
        switch state {
        case .working:
            let count = max(1, claude.workingCount)
            return count == 1 ? "Claude is working…" : "\(count) sessions working…"
        case .waiting:
            let count = claude.waitingCount
            return count == 1 ? "Your turn!" : "\(count) sessions need you"
        case .idle:
            return claude.isInstalled ? "Napping" : "Claude Code not installed"
        }
    }

    var body: some View {
        Animated(fps: state == .idle ? 2 : 6) { date in
            let tick = Int(date.timeIntervalSinceReferenceDate * (state == .idle ? 2 : 6))
            let mood: CrabSprite.Mood = {
                switch state {
                case .working: return .working
                case .waiting: return tick % 12 == 0 ? .blink : .happy
                case .idle: return .sleeping
                }
            }()
            let hop: CGFloat = state == .waiting ? (tick % 4 < 2 ? -6 : 0) : (state == .working ? (tick % 2 == 0 ? -1.5 : 0) : 0)
            VStack(spacing: model.family == .small ? 6 : 10) {
                ZStack(alignment: .topTrailing) {
                    CrabSprite(mood: mood, step: state == .working ? tick : 0)
                        .frame(maxWidth: model.family == .small ? 110 : 150)
                        .offset(y: hop)
                    if state == .idle {
                        Text(tick % 4 < 2 ? "z" : "Z")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .offset(x: 6, y: -16 - CGFloat(tick % 4) * 2)
                    } else if state == .working {
                        HStack(spacing: 3) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(Palette.claude.opacity(tick % 3 == index ? 1 : 0.3))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .offset(x: 4, y: -14)
                    }
                }
                .frame(maxHeight: .infinity)
                Text(caption)
                    .font(.system(size: model.family == .small ? 12 : 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(state == .waiting ? Color.green : (state == .working ? Palette.claude : Color.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if model.family != .small, let session = claude.sessions.first(where: { $0.state != .idle }) ?? claude.sessions.first {
                    Text(session.projectName + " · " + session.title)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .widgetPadding(16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let session = claude.sessions.first(where: { $0.state == .waiting }) ?? claude.sessions.first(where: { $0.state != .idle }) {
                claude.open(session)
            }
        }
        .monitoring(ClaudeMonitor.shared)
    }
}

// MARK: - Desktop pet

enum CrabPetKeys {
    static let reactsToClaude = ConfigKey("reactsToClaude", true)
    static let name = ConfigKey("name", "Clawd")
}

/// The crab wandering back and forth. Click it to make it jump.
struct CrabPetWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var claude = ClaudeMonitor.shared
    @State private var jumpStarted = Date.distantPast
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let reacts = model[CrabPetKeys.reactsToClaude]
        GeometryReader { geometry in
            Animated(fps: 12) { date in
                scene(date: date, size: geometry.size, reacts: reacts)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { jumpStarted = Date() }
        .monitoring(if: reacts, ClaudeMonitor.shared)
    }

    @ViewBuilder
    private func scene(date: Date, size: CGSize, reacts: Bool) -> some View {
        let time = date.timeIntervalSinceReferenceDate
        // The crab grows with the widget (limited by height, so wide sizes don't get a giant).
        let narrow = size.width < 200
        let crabWidth: CGFloat = min(size.width * (narrow ? 0.45 : 0.36), size.height * 0.5)
        let scale: CGFloat = crabWidth / 78
        let crabHeight = crabWidth / 18 * 6 * 1.6
        let travel = max(1, size.width - crabWidth - 24)
        // Walk back and forth, pausing at each end.
        let period = Double(travel / scale) / 22 + 3
        let phase = (time / period).truncatingRemainder(dividingBy: 2)
        let progress = min(1, max(0, (phase < 1 ? phase : 2 - phase) * 1.25 - 0.125))
        let facingLeft = phase >= 1
        let walking = progress > 0.001 && progress < 0.999
        let x = 12 + travel * CGFloat(progress)
        let sinceJump = Date().timeIntervalSince(jumpStarted)
        let jumpHeight: CGFloat = sinceJump < 0.6 ? CGFloat(sin(sinceJump / 0.6 * .pi)) * 30 * scale : 0
        let working = reacts && claude.workingCount > 0
        let waiting = reacts && claude.waitingCount > 0
        let tick = Int(time * 6)
        let mood: CrabSprite.Mood = jumpHeight > 0 || waiting ? .happy : (working ? .working : (tick % 25 == 0 ? .blink : .normal))
        let groundY = size.height - max(22, size.height * 0.1)

        ZStack(alignment: .topLeading) {
            // Ground line and a couple of pebbles.
            Capsule()
                .fill(Color.primary.opacity(0.12))
                .frame(width: size.width - 24, height: 3)
                .position(x: size.width / 2, y: groundY + 2)
            CrabSprite(mood: mood, step: walking ? tick : 0, facingLeft: facingLeft)
                .frame(width: crabWidth, height: crabHeight)
                .position(x: x + crabWidth / 2, y: groundY - crabHeight / 2 - jumpHeight)
            if working || waiting {
                Text(working ? "thinking…" : "your turn!")
                    .font(.system(size: 10 * max(1, scale * 0.8), weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                    .position(x: x + crabWidth / 2, y: groundY - crabHeight - 14 * max(1, scale) - jumpHeight)
            }
            Text(model[CrabPetKeys.name])
                .font(.system(size: 11 * max(1, scale * 0.8), weight: .semibold, design: .rounded))
                .foregroundStyle(style.tone(Palette.claude))
                .fixedSize()
                .padding(.leading, 14)
                .padding(.top, 10)
        }
    }
}

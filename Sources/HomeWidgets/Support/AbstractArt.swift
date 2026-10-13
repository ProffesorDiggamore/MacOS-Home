import SwiftUI

/// Generative abstract art in the spirit of Apple's wallpapers: soft blobs, folded
/// ribbons, layered waves, auroras, rings, facets and dunes. Everything is plain
/// maths from a seed, so the same seed always draws the same picture — at widget
/// size or at 6K for a desktop wallpaper.
enum ArtStyle: String, ConfigOption {
    case blobs, ribbons, waves, aurora, rings, facets, dunes, orbitals

    var label: String {
        switch self {
        case .blobs: return "Soft Blobs"
        case .ribbons: return "Ribbons"
        case .waves: return "Layered Waves"
        case .aurora: return "Aurora"
        case .rings: return "Rings"
        case .facets: return "Facets"
        case .dunes: return "Dunes"
        case .orbitals: return "Orbitals"
        }
    }
}

struct ArtPalette: Identifiable, Equatable {
    let id: String
    let name: String
    let colors: [UInt32] // first two make the backdrop gradient

    var swiftUI: [Color] { colors.map { Color(hex: $0) } }

    static let all: [ArtPalette] = [
        ArtPalette(id: "sonoma", name: "Sonoma", colors: [0x1B1F4A, 0x3A2A6B, 0xF2A65A, 0xE85D75, 0x6C5CE7, 0x00B8D9]),
        ArtPalette(id: "ventura", name: "Ventura", colors: [0x0B1026, 0x241E4E, 0xFF7A18, 0xAF002D, 0x319197, 0xFFD166]),
        ArtPalette(id: "sequoia", name: "Sequoia", colors: [0x07162B, 0x0E3A53, 0x2EC4B6, 0x9BE15D, 0x00A6FB, 0xF4F1DE]),
        ArtPalette(id: "bloom", name: "Bloom", colors: [0xFFF1E6, 0xFDE2E4, 0xFF8FAB, 0xC77DFF, 0x7BDFF2, 0xFFC6FF]),
        ArtPalette(id: "sunset", name: "Sunset", colors: [0x2B1055, 0x7597DE, 0xFF5E62, 0xFF9966, 0xFEC163, 0xDE4313]),
        ArtPalette(id: "ocean", name: "Ocean", colors: [0x021B2E, 0x03396C, 0x005B96, 0x6497B1, 0xB3CDE0, 0x00C2A8]),
        ArtPalette(id: "forest", name: "Forest", colors: [0x0B1D13, 0x1B3A26, 0x2D6A4F, 0x52B788, 0xB7E4C7, 0xD8F3DC]),
        ArtPalette(id: "candy", name: "Candy", colors: [0x2E0F45, 0x5B1A6E, 0xFF4E9B, 0xFFD23F, 0x3EC1D3, 0x9B5DE5]),
        ArtPalette(id: "mono", name: "Graphite", colors: [0x0D0D0F, 0x1C1C21, 0x3A3A44, 0x6E6E7A, 0xA9A9B3, 0xE4E4EB]),
        ArtPalette(id: "ember", name: "Ember", colors: [0x140A05, 0x3B0D0C, 0xD62828, 0xF77F00, 0xFCBF49, 0xEAE2B7]),
    ]

    static func named(_ id: String) -> ArtPalette { all.first { $0.id == id } ?? all[0] }
}

/// Deterministic random numbers for a seed.
struct ArtRandom {
    private var state: UInt64
    init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
}

struct AbstractArt: View {
    var style: ArtStyle
    var palette: ArtPalette
    var seed: Int
    /// Seconds for gentle motion; 0 for a still image.
    var time: Double = 0

    var body: some View {
        Canvas { context, size in
            Self.draw(style: style, palette: palette, seed: seed, time: time, in: &context, size: size)
        }
    }

    static func draw(style: ArtStyle, palette: ArtPalette, seed: Int, time: Double, in context: inout GraphicsContext, size: CGSize) {
        let colors = palette.swiftUI
        let rect = CGRect(origin: .zero, size: size)
        let unit = min(size.width, size.height)
        var random = ArtRandom(seed)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: [colors[0], colors[1]]),
                                                       startPoint: .zero, endPoint: CGPoint(x: size.width * 0.4, y: size.height)))
        let accents = Array(colors.dropFirst(2))
        func accent(_ i: Int) -> Color { accents[((i % accents.count) + accents.count) % accents.count] }

        switch style {
        case .blobs:
            var layer = context
            layer.addFilter(.blur(radius: unit * 0.14))
            for i in 0..<7 {
                let r = unit * random.range(0.22, 0.48)
                let x = size.width * random.range(-0.1, 1.1) + sin(time * 0.15 + Double(i)) * unit * 0.05
                let y = size.height * random.range(-0.1, 1.1) + cos(time * 0.12 + Double(i) * 1.7) * unit * 0.05
                layer.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(accent(i).opacity(0.85)))
            }

        case .ribbons:
            for i in 0..<5 {
                let thickness = unit * random.range(0.12, 0.28)
                let startY = size.height * random.range(0.1, 0.9)
                let endY = size.height * random.range(0.1, 0.9)
                let bend1 = size.height * random.range(-0.2, 1.2)
                let bend2 = size.height * random.range(-0.2, 1.2)
                let wobble = sin(time * 0.2 + Double(i)) * unit * 0.04
                var path = Path()
                path.move(to: CGPoint(x: -thickness, y: startY))
                path.addCurve(to: CGPoint(x: size.width + thickness, y: endY + wobble),
                              control1: CGPoint(x: size.width * 0.35, y: bend1 - wobble),
                              control2: CGPoint(x: size.width * 0.65, y: bend2 + wobble))
                var shadow = context
                shadow.addFilter(.blur(radius: thickness * 0.35))
                shadow.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                let shine = Gradient(colors: [accent(i).opacity(0.95), accent(i + 1).opacity(0.9), accent(i).opacity(0.7)])
                context.stroke(path, with: .linearGradient(shine, startPoint: CGPoint(x: 0, y: startY - thickness),
                                                           endPoint: CGPoint(x: size.width, y: endY + thickness)),
                               style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                context.stroke(path.offsetBy(dx: 0, dy: -thickness * 0.3), with: .color(.white.opacity(0.18)),
                               style: StrokeStyle(lineWidth: thickness * 0.12, lineCap: .round))
            }

        case .waves:
            let layers = 6
            for i in 0..<layers {
                let base = size.height * (0.35 + Double(i) * 0.11)
                let amplitude = unit * random.range(0.03, 0.09)
                let frequency = random.range(0.8, 2.2)
                let phase = random.range(0, .pi * 2) + time * (0.2 + Double(i) * 0.04)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for step in stride(from: 0.0, through: size.width, by: max(2, size.width / 240)) {
                    let p = step / size.width
                    let y = base + sin(p * .pi * 2 * frequency + phase) * amplitude + sin(p * .pi * 5 + phase * 0.7) * amplitude * 0.3
                    path.addLine(to: CGPoint(x: step, y: y))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(Gradient(colors: [accent(i).opacity(0.95), accent(i + 2).opacity(0.75)]),
                                                         startPoint: CGPoint(x: 0, y: base - amplitude), endPoint: CGPoint(x: size.width, y: size.height)))
            }

        case .aurora:
            var glow = context
            glow.addFilter(.blur(radius: unit * 0.06))
            let bands = 4
            for b in 0..<bands {
                let center = size.height * random.range(0.25, 0.6)
                let width = size.width / 90
                for k in 0..<90 {
                    let x = Double(k) * width
                    let wave = sin(Double(k) * 0.08 + Double(b) + time * 0.3) * unit * 0.08
                    let height = unit * random.range(0.15, 0.45)
                    let top = center + wave - height / 2
                    glow.fill(Path(CGRect(x: x, y: top, width: width * 1.6, height: height)),
                              with: .linearGradient(Gradient(colors: [.clear, accent(b).opacity(0.55), accent(b + 1).opacity(0.25), .clear]),
                                                    startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: top + height)))
                }
            }
            for _ in 0..<Int(size.width * size.height / 9000) {
                let star = CGRect(x: random.range(0, size.width), y: random.range(0, size.height * 0.6), width: 1.2, height: 1.2)
                context.fill(Path(ellipseIn: star), with: .color(.white.opacity(random.range(0.2, 0.8))))
            }

        case .rings:
            let centers = (0..<3).map { _ in CGPoint(x: size.width * random.range(0.1, 0.9), y: size.height * random.range(0.1, 0.9)) }
            for (n, center) in centers.enumerated() {
                let count = 22
                for i in (0..<count).reversed() {
                    let r = unit * 0.06 * Double(i + 1) + sin(time * 0.4 + Double(i) * 0.3) * unit * 0.004
                    var ring = context
                    ring.blendMode = .screen
                    ring.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                with: .color(accent(n + i).opacity(0.35)), lineWidth: unit * 0.018)
                }
            }

        case .facets:
            let columns = 9
            let rows = max(4, Int(Double(columns) * size.height / size.width) + 1)
            var points: [[CGPoint]] = []
            for r in 0...rows {
                var row: [CGPoint] = []
                for c in 0...columns {
                    let jitterX = (c == 0 || c == columns) ? 0 : random.range(-0.35, 0.35)
                    let jitterY = (r == 0 || r == rows) ? 0 : random.range(-0.35, 0.35)
                    row.append(CGPoint(x: (Double(c) + jitterX) * size.width / Double(columns),
                                       y: (Double(r) + jitterY) * size.height / Double(rows)))
                }
                points.append(row)
            }
            for r in 0..<rows {
                for c in 0..<columns {
                    let a = points[r][c], b = points[r][c + 1], d = points[r + 1][c], e = points[r + 1][c + 1]
                    for (index, tri) in [[a, b, e], [a, e, d]].enumerated() {
                        let cx = (tri[0].x + tri[1].x + tri[2].x) / 3 / size.width
                        let cy = (tri[0].y + tri[1].y + tri[2].y) / 3 / size.height
                        let mix = (cx * 0.6 + cy * 0.4 + sin(time * 0.3 + Double(r + c)) * 0.04)
                        let color = accent(Int(mix * Double(accents.count * 2)))
                        var path = Path()
                        path.addLines(tri)
                        path.closeSubpath()
                        context.fill(path, with: .color(color.opacity(0.55 + 0.35 * Double((r + c + index) % 3) / 2)))
                        context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.6)
                    }
                }
            }

        case .dunes:
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.62, y: size.height * 0.12, width: unit * 0.22, height: unit * 0.22)),
                         with: .color(accent(3).opacity(0.9)))
            for i in 0..<5 {
                let base = size.height * (0.45 + Double(i) * 0.12)
                let a1 = unit * random.range(0.04, 0.12), f1 = random.range(0.5, 1.4), p1 = random.range(0, 6)
                let a2 = unit * random.range(0.01, 0.04), f2 = random.range(2, 4)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))
                for step in stride(from: 0.0, through: size.width, by: max(2, size.width / 200)) {
                    let p = step / size.width
                    path.addLine(to: CGPoint(x: step, y: base - sin(p * .pi * f1 + p1 + time * 0.05) * a1 - sin(p * .pi * f2) * a2))
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                context.fill(path, with: .linearGradient(Gradient(colors: [accent(i), accent(i).opacity(0.6)]),
                                                         startPoint: CGPoint(x: 0, y: base - a1), endPoint: CGPoint(x: size.width * 0.3, y: size.height)))
            }

        case .orbitals:
            let center = CGPoint(x: size.width * random.range(0.3, 0.7), y: size.height * random.range(0.3, 0.7))
            var glow = context
            glow.addFilter(.blur(radius: unit * 0.08))
            glow.fill(Path(ellipseIn: CGRect(x: center.x - unit * 0.18, y: center.y - unit * 0.18, width: unit * 0.36, height: unit * 0.36)),
                      with: .color(accent(0).opacity(0.7)))
            for i in 0..<7 {
                let rx = unit * (0.12 + Double(i) * 0.09)
                let ry = rx * random.range(0.3, 0.7)
                let tilt = Angle.degrees(random.range(-35, 35))
                var orbit = context
                orbit.translateBy(x: center.x, y: center.y)
                orbit.rotate(by: tilt)
                orbit.stroke(Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)), with: .color(.white.opacity(0.12)), lineWidth: 1)
                let angle = random.range(0, .pi * 2) + time * (0.5 / Double(i + 1))
                let planet = CGPoint(x: cos(angle) * rx, y: sin(angle) * ry)
                let pr = unit * random.range(0.012, 0.03)
                orbit.fill(Path(ellipseIn: CGRect(x: planet.x - pr, y: planet.y - pr, width: pr * 2, height: pr * 2)), with: .color(accent(i + 1)))
            }
        }

        // A whisper of grain so big gradients don't band on wallpapers.
        if unit > 600 {
            var grain = ArtRandom(seed &+ 99)
            for _ in 0..<Int(size.width * size.height / 1600) {
                let dot = CGRect(x: grain.range(0, size.width), y: grain.range(0, size.height), width: 1, height: 1)
                context.fill(Path(dot), with: .color(.white.opacity(0.035)))
            }
        }
    }
}

import Foundation
import CoreGraphics
import CoreText
import simd

/// Poster-style wallpapers: liquid glass over big type, and a chaotic attractor plotted point by point.
enum PosterScenes {
    // MARK: - Glass type

    private static let characters = Array("水滴透明静光雨流空澄泡音波硝子結晶氷霧淡")

    /// Metaball droplets (they merge where they touch) refracting a poster of oversized characters.
    static func glassType(width: Int, height: Int, palette: InkPalette, dice: Dice) -> CGImage? {
        guard let canvas = InkCanvas(width: width, height: height, palette: palette) else { return nil }
        let (w, h, u) = (canvas.width, canvas.height, canvas.unit)
        let grey = InkPalette.RGB(palette.paper.r * 0.55 + palette.ink.r * 0.45, palette.paper.g * 0.55 + palette.ink.g * 0.45,
                                  palette.paper.b * 0.55 + palette.ink.b * 0.45)

        // Hairline rules and small captions, like a printed poster.
        for y in [h * dice.range(0.12, 0.2), h * dice.range(0.8, 0.9)] {
            canvas.pen([CGPoint(x: 0, y: y), CGPoint(x: w, y: y)], width: 1.4 * u, alpha: 0.5, color: grey)
        }
        drawText(canvas, "Home Widgets", at: CGPoint(x: w - 40 * u, y: 40 * u), size: 34 * u, weight: "HiraginoSans-W3", color: grey, alignRight: true)
        drawText(canvas, "水滴の研究", at: CGPoint(x: 60 * u, y: h * 0.3), size: 22 * u, weight: "HiraginoSans-W3", color: grey)
        drawText(canvas, "Glass Study Nº \(dice.int(10, 99))", at: CGPoint(x: 60 * u, y: h * 0.3 + 30 * u), size: 22 * u, weight: "HiraginoSans-W3", color: grey)

        // Columns of huge characters, some turned on their side, one in solid ink.
        let columns = dice.int(4, 6)
        let size = h * dice.range(0.15, 0.2)
        let left = w * dice.range(0.18, 0.3)
        let inked = dice.int(0, columns - 1)
        for column in 0..<columns {
            let x = left + CGFloat(column) * size * 1.08
            var y = h * dice.range(0.18, 0.3)
            for _ in 0..<dice.int(2, 4) where y < h * 0.85 {
                let char = String(characters[dice.int(0, characters.count - 1)])
                drawGlyph(canvas, char, center: CGPoint(x: x + size / 2, y: y + size / 2), size: size,
                          turned: dice.chance(0.3) ? (dice.chance(0.5) ? .pi / 2 : -.pi / 2) : 0,
                          mirrored: dice.chance(0.2), color: column == inked && dice.chance(0.7) ? palette.ink : grey)
                y += size * dice.range(0.95, 1.1)
            }
        }
        canvas.finish(seed: dice.int(1, 99999), grain: 7, vignette: 0.04)
        guard let poster = canvas.image, let background = Raster(image: poster, width: width, height: height) else { return nil }

        // The droplets: a merged cluster winding across the middle, plus loose bubbles.
        struct Ball { var x: Float; var y: Float; var r: Float }
        let fw = Float(width), fh = Float(height)
        var balls: [Ball] = []
        // A cluster of touching drops over the middle of the type, so they have something to bend.
        let blockCenter = SIMD2<Float>(Float(left + size * CGFloat(columns) / 2), fh * Float(dice.range(0.45, 0.58)))
        let blockReach = SIMD2<Float>(Float(size * CGFloat(columns)) * 0.42, fh * 0.28)
        let wanted = dice.int(7, 12)
        var attempts = 0
        while balls.count < wanted && attempts < 600 {
            attempts += 1
            let r = fh * Float(dice.range(0.035, 0.115))
            let angle = Float(dice.range(0, 2 * .pi)), distance = Float(dice.next()).squareRoot()
            let p = blockCenter + SIMD2(cos(angle), sin(angle)) * blockReach * distance
            let crowded = balls.contains { simd_distance(p, SIMD2($0.x, $0.y)) < ($0.r + r) * 0.82 }
            let touching = balls.isEmpty || balls.contains { simd_distance(p, SIMD2($0.x, $0.y)) < ($0.r + r) * 1.06 }
            if !crowded && touching { balls.append(Ball(x: p.x, y: p.y, r: r)) }
        }
        for _ in 0..<dice.int(6, 11) {
            balls.append(Ball(x: fw * Float(dice.range(0.05, 0.95)), y: fh * Float(dice.range(0.05, 0.95)), r: fh * Float(dice.range(0.012, 0.045))))
        }

        var output = background
        let light = SIMD3<Float>(palette.isDark ? palette.ink : palette.paper) * 1.02
        let darkEdge = SIMD3<Float>(palette.isDark ? palette.paper : palette.ink)
        let lamp = normalize(SIMD3<Float>(-0.45, -0.65, 0.62))
        let minX = max(0, Int(balls.map { $0.x - $0.r * 1.8 }.min() ?? 0)), maxX = min(width, Int(balls.map { $0.x + $0.r * 1.8 }.max() ?? 0))
        let minY = max(0, Int(balls.map { $0.y - $0.r * 1.8 }.min() ?? 0)), maxY = min(height, Int(balls.map { $0.y + $0.r * 1.8 }.max() ?? 0))
        for y in minY..<maxY {
            let py = Float(y) + 0.5
            for x in minX..<maxX {
                let px = Float(x) + 0.5
                // Field: each drop adds (r²/d²)², so drops stay round and only merge where they meet.
                var field: Float = 0, fx: Float = 0, fy: Float = 0, weighted: Float = 0
                for ball in balls {
                    let dx = px - ball.x, dy = py - ball.y
                    let d2 = dx * dx + dy * dy + 1
                    let b = ball.r * ball.r / d2
                    let k = b * b
                    field += k
                    weighted += k * ball.r
                    let pull = -4 * k / d2
                    fx += pull * dx
                    fy += pull * dy
                }
                let g = field.squareRoot()
                let gx = fx / (2 * g), gy = fy / (2 * g)
                let steep = (gx * gx + gy * gy).squareRoot()
                guard g > 1 - steep * 1.5 else { continue }
                // Height sqrt(1 - 1/g) is an exact hemisphere for a single drop; its slope gives the normal.
                let radius = weighted / field
                let lift = max(0.02, (max(0, 1 - 1 / g)).squareRoot())
                let sx = -gx / (2 * lift * g * g) * radius, sy = -gy / (2 * lift * g * g) * radius
                let n = simd_normalize(SIMD3<Float>(sx, sy, 1))
                let nz = n.z
                // Refraction: the background seen through the drop, pulled in toward the middle.
                var c = background.sample(px - n.x * radius * 0.85, py - n.y * radius * 0.85)
                c = (c - 0.5) * 1.25 + 0.5
                // Reflection of a soft studio: bright above-left, dark below-right; strongest at grazing angles.
                let r = SIMD3<Float>(2 * nz * n.x, 2 * nz * n.y, 2 * nz * nz - 1)
                let up = -r.y * 0.8 - r.x * 0.45
                // A dark room with one big window up and to the left.
                let window = smoothstep(0.45, 0.6, up) * (1 - smoothstep(0.85, 0.95, up))
                let environment = darkEdge.mixed(with: light, max(window, 0.25 * smoothstep(-0.4, 0.4, up)))
                let fresnel: Float = 0.06 + 0.94 * pow(1 - nz, 2.2)
                c = c.mixed(with: environment, fresnel)
                c *= 1 - 0.5 * smoothstep(0.38, 0.05, nz)
                let shine = pow(max(0, simd_dot(r, lamp)), 70) * 1.6 + pow(max(0, simd_dot(r, lamp)), 8) * 0.12
                c += SIMD3(repeating: shine)
                let caustic = max(0, n.x * 0.55 + n.y * 0.8) * smoothstep(0.1, 0.6, 1 - nz) * (1 - smoothstep(0.75, 1, 1 - nz))
                c += light * caustic * 0.28
                // Antialiased rim.
                let coverage = min(1, max(0, (g - 1) / max(0.0001, steep * 1.5) + 1))
                output.set(x, y, background.get(x, y).mixed(with: c, coverage))
            }
        }
        return output.image()
    }

    private static func font(_ name: String, _ size: CGFloat) -> CTFont {
        CTFontCreateWithName(name as CFString, size, nil)
    }

    private static func line(_ text: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// Text with its top-left (or top-right) corner at `point`, in the canvas's top-left coordinates.
    private static func drawText(_ canvas: InkCanvas, _ text: String, at point: CGPoint, size: CGFloat, weight: String,
                                 color: InkPalette.RGB, alignRight: Bool = false) {
        let ctLine = line(text, font: font(weight, size), color: canvas.color(color, 0.9))
        let width = CTLineGetTypographicBounds(ctLine, nil, nil, nil)
        let context = canvas.context
        context.saveGState()
        context.translateBy(x: alignRight ? point.x - CGFloat(width) : point.x, y: point.y + size)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }

    private static func drawGlyph(_ canvas: InkCanvas, _ text: String, center: CGPoint, size: CGFloat, turned: CGFloat,
                                  mirrored: Bool, color: InkPalette.RGB) {
        let ctLine = line(text, font: font("HiraginoSans-W8", size), color: canvas.color(color, 0.92))
        let bounds = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
        let context = canvas.context
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: turned)
        context.scaleBy(x: mirrored ? -1 : 1, y: -1)
        context.textPosition = CGPoint(x: -bounds.midX, y: -bounds.midY)
        CTLineDraw(ctLine, context)
        context.restoreGState()
    }

    // MARK: - Attractor

    /// Clifford attractor: x' = sin(a·y) + c·cos(a·x), y' = sin(b·x) + d·cos(b·y).
    private static let presets: [SIMD4<Float>] = [
        SIMD4(-1.4, 1.6, 1.0, 0.7), SIMD4(1.7, 1.7, 0.6, 1.2), SIMD4(-1.7, 1.3, -0.1, -1.2), SIMD4(-1.8, -2.0, -0.5, -0.9),
        SIMD4(1.5, -1.8, 1.6, 0.9), SIMD4(-1.7, 1.8, -1.9, -0.4), SIMD4(1.1, -1.32, -1.03, 1.54), SIMD4(-1.24, -1.25, -1.81, -1.91),
    ]

    static func attractor(width: Int, height: Int, palette: InkPalette, dice: Dice) -> CGImage? {
        var p = presets[dice.int(0, presets.count - 1)]
        p += SIMD4(Float(dice.range(-0.06, 0.06)), Float(dice.range(-0.06, 0.06)), Float(dice.range(-0.06, 0.06)), Float(dice.range(-0.06, 0.06)))
        func step(_ v: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2(sin(p.x * v.y) + p.z * cos(p.x * v.x), sin(p.y * v.x) + p.w * cos(p.y * v.y))
        }
        // Find the shape's extent first, then fit it to the screen with a margin.
        var v = SIMD2<Float>(0.1, 0.1)
        var low = SIMD2<Float>(repeating: .greatestFiniteMagnitude), high = SIMD2<Float>(repeating: -.greatestFiniteMagnitude)
        for i in 0..<60_000 {
            v = step(v)
            if i > 100 { low = simd_min(low, v); high = simd_max(high, v) }
        }
        let span = simd_max(high - low, SIMD2(repeating: 0.001))
        let margin: Float = 0.06
        let scale = SIMD2(Float(width) * (1 - 2 * margin) / span.x, Float(height) * (1 - 2 * margin) / span.y)
        let offset = SIMD2(Float(width) * margin, Float(height) * margin)

        var counts = [Float](repeating: 0, count: width * height)
        var flow = [Float](repeating: 0, count: width * height)
        let iterations = width * height * 7
        for _ in 0..<iterations {
            let next = step(v)
            let pixel = (next - low) * scale + offset
            let x = Int(pixel.x), y = Int(pixel.y)
            if x >= 0, y >= 0, x < width, y < height {
                let i = y * width + x
                counts[i] += 1
                flow[i] += next.x - v.x > 0 ? 1 : -1
            }
            v = next
        }
        // Log density so faint trails and dense cores both show.
        let peak = counts.max() ?? 1
        let norm = log(1 + peak * 0.25)
        let paper = SIMD3<Float>(palette.paper), ink = SIMD3<Float>(palette.ink), tint = SIMD3<Float>(palette.tint)
        var image = Raster(width: width, height: height, fill: paper)
        for i in 0..<(width * height) where counts[i] > 0 {
            let density = min(1, log(1 + counts[i]) / norm)
            let direction = flow[i] / counts[i] * 0.5 + 0.5
            let color = tint.mixed(with: ink, 0.35 + 0.65 * direction)
            image.set(i % width, i / width, paper.mixed(with: color, pow(density, 0.62)))
        }
        guard let plot = image.image() else { return nil }
        guard let canvas = InkCanvas(width: width, height: height, palette: palette) else { return plot }
        canvas.paste(fromImage: plot)
        let u = canvas.unit
        let caption = String(format: "x′ = sin(%.2f·y) + %.2f·cos(%.2f·x)    y′ = sin(%.2f·x) + %.2f·cos(%.2f·y)", p.x, p.z, p.x, p.y, p.w, p.y)
        drawText(canvas, caption, at: CGPoint(x: 40 * u, y: canvas.height - 56 * u), size: 15 * u, weight: "Menlo-Regular",
                 color: palette.ink)
        return canvas.image
    }
}

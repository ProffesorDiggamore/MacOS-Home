import Foundation
import CoreGraphics
import CoreImage

/// Wallpapers drawn on the CPU: ink sketches, posters, glitch art and pixel art. Unlike the
/// studio renders these are built stroke by stroke or pixel by pixel.
enum SketchScene: String, CaseIterable, Identifiable {
    case powerLines, inkBranch, inkLotus, inkMountains
    case glassType, attractor
    case datamosh, pixelSort, melt
    case pixelNight, pixelChrome, asciiChrome

    enum Group { case sketch, poster, glitch, pixel }

    var id: String { rawValue }
    var label: String {
        switch self {
        case .powerLines: return "Power Lines"
        case .inkBranch: return "Plum Blossom"
        case .inkLotus: return "Ink Lotus"
        case .inkMountains: return "Misty Peaks"
        case .glassType: return "Glass Type"
        case .attractor: return "Attractor"
        case .datamosh: return "Datamosh"
        case .pixelSort: return "Pixel Sort"
        case .melt: return "Chrome Melt"
        case .pixelNight: return "Pixel Night"
        case .pixelChrome: return "Dithered Chrome"
        case .asciiChrome: return "ASCII"
        }
    }
    var summary: String {
        switch self {
        case .powerLines: return "Scratchy pen sketch of poles and tangled wires"
        case .inkBranch: return "A gnarled plum tree in full bloom, brush and ink"
        case .inkLotus: return "A crowded sumi-e lotus pond on rice paper"
        case .inkMountains: return "Peaks, pines and waterfalls fading into mist"
        case .glassType: return "Liquid glass droplets bending big type behind them"
        case .attractor: return "Millions of points from one chaotic equation"
        case .datamosh: return "A mossy waterfall, corrupted into blocks and drips"
        case .pixelSort: return "Marbled noise with its pixels sorted into streaks"
        case .melt: return "Liquid chrome glitched, smeared and dripping"
        case .pixelNight: return "A 1-bit moonlit lake, dithered like an old Mac"
        case .pixelChrome: return "Liquid chrome printed in big dithered pixels"
        case .asciiChrome: return "Liquid chrome drawn entirely in characters"
        }
    }
    var group: Group {
        switch self {
        case .powerLines, .inkBranch, .inkLotus, .inkMountains: return .sketch
        case .glassType, .attractor: return .poster
        case .datamosh, .pixelSort, .melt: return .glitch
        case .pixelNight, .pixelChrome, .asciiChrome: return .pixel
        }
    }
}

/// Paper and ink for each tone. Light tones are black ink on paper; dark ones are pale ink on black.
struct InkPalette {
    typealias RGB = (r: CGFloat, g: CGFloat, b: CGFloat)
    var paper: RGB
    var ink: RGB
    var accent: RGB // seal stamps and the sun
    var bloom: RGB // flowers
    var isDark: Bool
    /// The colour gradients lean toward (glitch art, attractors). Neutral tones keep it grey.
    var tint: RGB

    /// The darker and lighter of paper and ink, for pixel art that should read as night either way.
    var dark: RGB { isDark ? paper : ink }
    var light: RGB { isDark ? ink : paper }

    /// Dark to light through the tint: five stops for mapping brightness to colour.
    var ramp: [SIMD3<Float>] {
        func v(_ c: RGB) -> SIMD3<Float> { SIMD3(Float(c.r), Float(c.g), Float(c.b)) }
        let (d, t, l) = (v(dark), v(tint), v(light))
        return [d, d * 0.45 + t * 0.55, t, t * 0.45 + l * 0.55, l]
    }
}

extension StudioTone {
    var ink: InkPalette {
        switch self {
        case .pearl:
            return InkPalette(paper: (0.955, 0.948, 0.93), ink: (0.06, 0.06, 0.065), accent: (0.76, 0.16, 0.13), bloom: (0.97, 0.96, 0.95), isDark: false, tint: (0.55, 0.56, 0.58))
        case .silver:
            return InkPalette(paper: (0.83, 0.835, 0.845), ink: (0.09, 0.09, 0.1), accent: (0.66, 0.17, 0.15), bloom: (0.93, 0.93, 0.94), isDark: false, tint: (0.5, 0.52, 0.55))
        case .prism:
            return InkPalette(paper: (0.925, 0.895, 0.83), ink: (0.09, 0.075, 0.06), accent: (0.78, 0.2, 0.14), bloom: (0.95, 0.72, 0.76), isDark: false, tint: (0.62, 0.5, 0.52))
        case .obsidian:
            return InkPalette(paper: (0.04, 0.04, 0.045), ink: (0.9, 0.9, 0.89), accent: (0.82, 0.26, 0.22), bloom: (0.92, 0.92, 0.92), isDark: true, tint: (0.42, 0.42, 0.43))
        case .midnight:
            return InkPalette(paper: (0.035, 0.055, 0.12), ink: (0.78, 0.85, 0.97), accent: (0.95, 0.72, 0.38), bloom: (0.85, 0.9, 1.0), isDark: true, tint: (0.3, 0.42, 0.75))
        case .moss, .custom:
            let colors = self.colors ?? CustomTone.standard
            func c(_ v: SIMD3<Float>) -> InkPalette.RGB { (CGFloat(v.x), CGFloat(v.y), CGFloat(v.z)) }
            let bloom = colors.ink * 0.6 + colors.accent * 0.4
            return InkPalette(paper: c(colors.background), ink: c(colors.ink), accent: c(colors.accent), bloom: c(bloom),
                              isDark: colors.isDark, tint: c(colors.accent))
        }
    }
}

enum SketchRenderer {
    static func render(_ scene: SketchScene, tone: StudioTone, seed: Int, width: Int, height: Int,
                       progress: ((Double) -> Void)? = nil) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let palette = tone.ink
        let dice = Dice(seed &* 7919 &+ scene.rawValue.count)
        progress?(0.1)
        let image: CGImage?
        switch scene {
        case .pixelNight:
            image = PixelScenes.night(width: width, height: height, palette: palette, dice: dice)
        case .pixelChrome:
            image = PixelScenes.ditheredChrome(width: width, height: height, palette: palette, seed: seed)
        case .asciiChrome:
            image = PixelScenes.ascii(width: width, height: height, palette: palette, seed: seed)
        case .datamosh:
            image = GlitchScenes.datamosh(width: width, height: height, tone: tone, palette: palette, seed: seed, dice: dice)
        case .pixelSort:
            image = GlitchScenes.pixelSort(width: width, height: height, palette: palette, dice: dice)
        case .melt:
            image = GlitchScenes.melt(width: width, height: height, tone: tone, seed: seed, dice: dice)
        case .glassType:
            image = PosterScenes.glassType(width: width, height: height, palette: palette, dice: dice)
        case .attractor:
            image = PosterScenes.attractor(width: width, height: height, palette: palette, dice: dice)
        case .powerLines, .inkBranch, .inkLotus, .inkMountains:
            guard let canvas = InkCanvas(width: width, height: height, palette: palette) else { return nil }
            canvas.paperTexture(dice)
            switch scene {
            case .powerLines: SketchScenes.powerLines(canvas, dice)
            case .inkBranch: SketchScenes.inkBranch(canvas, dice)
            case .inkLotus: InkScenes.lotus(canvas, dice)
            default: InkScenes.mountains(canvas, dice)
            }
            progress?(0.85)
            canvas.finish(seed: seed)
            image = canvas.image
        }
        progress?(1)
        return image
    }

    // MARK: Shared helpers

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// A soft copy of a layer, for ink that bleeds into the paper.
    static func blur(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(radius)).cropped(to: input.extent)
        return ciContext.createCGImage(output, from: input.extent)
    }

    /// Catmull-Rom curve through the points, so hand-placed points become smooth strokes.
    static func smooth(_ points: [CGPoint], steps: Int = 8) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var out: [CGPoint] = []
        out.reserveCapacity(points.count * steps)
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            for s in 0..<steps {
                let t = CGFloat(s) / CGFloat(steps)
                out.append(CGPoint(x: spline(p0.x, p1.x, p2.x, p3.x, t), y: spline(p0.y, p1.y, p2.y, p3.y, t)))
            }
        }
        out.append(points[points.count - 1])
        return out
    }

    private static func spline(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
        let t2: CGFloat = t * t
        let t3: CGFloat = t2 * t
        let k1: CGFloat = (c - a) * t
        let k2: CGFloat = (2 * a - 5 * b + 4 * c - d) * t2
        let k3: CGFloat = (3 * b - a - 3 * c + d) * t3
        return 0.5 * (2 * b + k1 + k2 + k3)
    }

    /// Pushes each point sideways by smooth noise, so ruled lines look drawn by hand.
    static func wobble(_ points: [CGPoint], amount: CGFloat, frequency: CGFloat, noise: Noise1D, phase: CGFloat) -> [CGPoint] {
        guard points.count > 1, amount > 0 else { return points }
        return points.indices.map { i in
            let prev = points[max(i - 1, 0)], next = points[min(i + 1, points.count - 1)]
            let dx = next.x - prev.x, dy = next.y - prev.y
            let length = max(0.0001, hypot(dx, dy))
            let push = amount * noise(CGFloat(i) * frequency + phase)
            return CGPoint(x: points[i].x - dy / length * push, y: points[i].y + dx / length * push)
        }
    }

    /// Points along a straight line.
    static func line(_ a: CGPoint, _ b: CGPoint, steps: Int) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }

    /// A hanging wire between two points.
    static func catenary(_ a: CGPoint, _ b: CGPoint, sag: CGFloat, steps: Int = 40) -> [CGPoint] {
        (0...steps).map { i in
            let t = CGFloat(i) / CGFloat(steps)
            let droop: CGFloat = sag * 4 * t * (1 - t)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + droop)
        }
    }
}

/// A sheet of paper to draw on, with the origin at the top-left and sizes in `unit`s
/// (a thousandth of the height), so a drawing looks the same at every resolution.
final class InkCanvas {
    typealias RGB = InkPalette.RGB
    let context: CGContext
    let width: CGFloat
    let height: CGFloat
    let unit: CGFloat
    let palette: InkPalette

    init?(width: Int, height: Int, palette: InkPalette, transparent: Bool = false) {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        self.context = context
        self.width = CGFloat(width)
        self.height = CGFloat(height)
        unit = CGFloat(height) / 1000
        self.palette = palette
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.interpolationQuality = .high
        if !transparent {
            context.setFillColor(color(palette.paper, 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A blank, see-through sheet the same size, for a layer that gets blurred or faded.
    func layer() -> InkCanvas? {
        InkCanvas(width: context.width, height: context.height, palette: palette, transparent: true)
    }

    var image: CGImage? { context.makeImage() }

    func color(_ rgb: RGB, _ alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    /// Lays a finished layer (optionally softened) over this one.
    func paste(_ other: InkCanvas, blur radius: CGFloat = 0, alpha: CGFloat = 1) {
        guard var image = other.image else { return }
        if radius > 0.5, let soft = SketchRenderer.blur(image, radius: radius) { image = soft }
        paste(fromImage: image, alpha: alpha)
    }

    /// Draws a full-size image over the canvas.
    func paste(fromImage image: CGImage, alpha: CGFloat = 1) {
        context.saveGState()
        // Images draw in the bitmap's own (bottom-up) space, so undo the flip.
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -height)
        context.setAlpha(alpha)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }

    // MARK: Marks

    func pen(_ points: [CGPoint], width: CGFloat, alpha: CGFloat, color rgb: RGB? = nil) {
        guard points.count > 1 else { return }
        context.beginPath()
        context.addLines(between: points)
        context.setLineWidth(width)
        context.setStrokeColor(color(rgb ?? palette.ink, alpha))
        context.strokePath()
    }

    func fill(_ path: CGPath, alpha: CGFloat, color rgb: RGB? = nil) {
        context.addPath(path)
        context.setFillColor(color(rgb ?? palette.ink, alpha))
        context.fillPath()
    }

    func polygon(_ points: [CGPoint], alpha: CGFloat, color rgb: RGB? = nil) {
        guard points.count > 2 else { return }
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        fill(path, alpha: alpha, color: rgb)
    }

    func dot(_ center: CGPoint, radius: CGFloat, alpha: CGFloat, color rgb: RGB? = nil) {
        context.setFillColor(color(rgb ?? palette.ink, alpha))
        context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// A brush stroke that swells and tapers along its length (`width` gets 0…1 along the stroke).
    func brush(_ points: [CGPoint], width: (CGFloat) -> CGFloat, alpha: CGFloat, color rgb: RGB? = nil) {
        let n = points.count
        guard n > 1 else { return }
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        left.reserveCapacity(n)
        right.reserveCapacity(n)
        for i in 0..<n {
            let prev = points[max(i - 1, 0)], next = points[min(i + 1, n - 1)]
            let dx = next.x - prev.x, dy = next.y - prev.y
            let length = max(0.0001, hypot(dx, dy))
            let half = width(CGFloat(i) / CGFloat(n - 1)) / 2
            let nx: CGFloat = -dy / length * half
            let ny: CGFloat = dx / length * half
            left.append(CGPoint(x: points[i].x + nx, y: points[i].y + ny))
            right.append(CGPoint(x: points[i].x - nx, y: points[i].y - ny))
        }
        polygon(left + right.reversed(), alpha: alpha, color: rgb)
    }

    /// Streaks of paper showing through a fast brush stroke ("flying white").
    func dryBrush(_ points: [CGPoint], width: CGFloat, streaks: Int, dice: Dice, alpha: CGFloat = 0.45, broken: Bool = false) {
        guard points.count > 3 else { return }
        for _ in 0..<streaks {
            let offset = dice.range(-0.4, 0.4) * width
            var run: [CGPoint] = []
            let gapChance = broken ? dice.range(0.1, 0.25) : dice.range(0.02, 0.08)
            for i in points.indices {
                let prev = points[max(i - 1, 0)], next = points[min(i + 1, points.count - 1)]
                let dx = next.x - prev.x, dy = next.y - prev.y
                let length = max(0.0001, hypot(dx, dy))
                run.append(CGPoint(x: points[i].x - dy / length * offset, y: points[i].y + dx / length * offset))
                if dice.chance(gapChance) {
                    if !broken || dice.chance(0.6) {
                        pen(run, width: dice.range(0.3, 0.9) * unit, alpha: alpha, color: palette.paper)
                    }
                    run = []
                }
            }
            pen(run, width: dice.range(0.3, 0.9) * unit, alpha: alpha, color: palette.paper)
        }
    }

    /// A line drawn two or three times by a quick hand: slightly different each pass.
    func sketchLine(_ points: [CGPoint], width: CGFloat, alpha: CGFloat, dice: Dice, noise: Noise1D, passes: Int = 2) {
        for pass in 0..<passes {
            let shaky = SketchRenderer.wobble(points, amount: unit * dice.range(0.6, 1.8), frequency: 0.13,
                                              noise: noise, phase: dice.range(0, 200))
            pen(shaky, width: width * (pass == 0 ? 1 : dice.range(0.5, 0.9)), alpha: alpha * (pass == 0 ? 1 : 0.6))
        }
    }

    /// Paper-coloured haze that thickens downward, hiding whatever is behind it.
    func mist(from top: CGFloat, to bottom: CGFloat, strength: CGFloat = 0.93) {
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [color(palette.paper, 0), color(palette.paper, strength)] as CFArray,
                                        locations: [0, 1]) else { return }
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: top, width: width, height: height - top))
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [.drawsAfterEndLocation])
        context.restoreGState()
    }

    // MARK: Paper

    /// Faint blotches so the paper isn't perfectly flat.
    func paperTexture(_ dice: Dice) {
        guard let wash = layer() else { return }
        for _ in 0..<14 {
            let center = CGPoint(x: dice.range(0, width), y: dice.range(0, height))
            wash.dot(center, radius: dice.range(80, 320) * unit, alpha: dice.range(0.012, 0.03))
        }
        paste(wash, blur: 90 * unit)
    }

    /// Grain and a soft vignette, applied straight to the pixels.
    func finish(seed: Int, grain: Float = 9, vignette: Float = 0.11) {
        guard let data = context.data else { return }
        let w = context.width, h = context.height, stride = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: stride * h)
        var state = UInt32(truncatingIfNeeded: seed &* 2_654_435_761) | 1
        let cx = Float(w) / 2, cy = Float(h) / 2
        let inverse: Float = 1 / (cx * cx + cy * cy)
        for y in 0..<h {
            let dy = Float(y) - cy
            let row = y * stride
            for x in 0..<w {
                state ^= state << 13
                state ^= state >> 17
                state ^= state << 5
                let noise = (Float(state & 0xFF) / 255 - 0.5) * grain
                let dx = Float(x) - cx
                let shade: Float = 1 - vignette * (dx * dx + dy * dy) * inverse
                let index = row + x * 4
                for channel in 0..<3 {
                    let value = Float(pixels[index + channel]) * shade + noise
                    pixels[index + channel] = UInt8(max(0, min(255, value)))
                }
            }
        }
    }

    // MARK: Calligraphy

    /// A column of made-up brush characters, the way ink paintings carry a poem down one side.
    func calligraphy(x: CGFloat, top: CGFloat, characters: Int, size: CGFloat, dice: Dice, alpha: CGFloat = 0.85) {
        var y = top
        for _ in 0..<characters {
            glyph(in: CGRect(x: x - size / 2, y: y, width: size, height: size), dice: dice, alpha: alpha)
            y += size * dice.range(1.15, 1.35)
        }
    }

    private func glyph(in box: CGRect, dice: Dice, alpha: CGFloat) {
        let strokes = dice.int(3, 7)
        for _ in 0..<strokes {
            let kind = dice.int(0, 4)
            let a: CGPoint, b: CGPoint
            switch kind {
            case 0: // horizontal, rising a little
                let y = box.minY + dice.range(0.1, 0.9) * box.height
                a = CGPoint(x: box.minX + dice.range(0, 0.3) * box.width, y: y)
                b = CGPoint(x: box.maxX - dice.range(0, 0.3) * box.width, y: y - box.height * 0.05)
            case 1: // vertical
                let x = box.minX + dice.range(0.15, 0.85) * box.width
                a = CGPoint(x: x, y: box.minY + dice.range(0, 0.3) * box.height)
                b = CGPoint(x: x, y: box.maxY - dice.range(0, 0.25) * box.height)
            case 2: // falling left
                a = CGPoint(x: box.midX + dice.range(-0.1, 0.25) * box.width, y: box.minY + dice.range(0.05, 0.4) * box.height)
                b = CGPoint(x: box.minX + dice.range(0, 0.2) * box.width, y: box.maxY - dice.range(0, 0.15) * box.height)
            case 3: // falling right
                a = CGPoint(x: box.midX + dice.range(-0.25, 0.1) * box.width, y: box.minY + dice.range(0.2, 0.5) * box.height)
                b = CGPoint(x: box.maxX - dice.range(0, 0.1) * box.width, y: box.maxY - dice.range(0, 0.1) * box.height)
            default: // dot
                let c = CGPoint(x: box.minX + dice.range(0.2, 0.8) * box.width, y: box.minY + dice.range(0.1, 0.9) * box.height)
                dot(c, radius: box.width * dice.range(0.05, 0.08), alpha: alpha)
                continue
            }
            let mid = CGPoint(x: (a.x + b.x) / 2 + dice.range(-0.06, 0.06) * box.width, y: (a.y + b.y) / 2 + dice.range(-0.06, 0.06) * box.height)
            let points = SketchRenderer.smooth([a, mid, b], steps: 10)
            let weight = box.width * dice.range(0.07, 0.12)
            brush(points, width: { t in weight * (0.55 + 0.45 * sin(.pi * min(1, t * 1.2 + 0.1))) }, alpha: alpha)
        }
    }

    /// A small red seal stamp with carved lines.
    func seal(at origin: CGPoint, size: CGFloat, dice: Dice) {
        let rect = CGRect(x: origin.x, y: origin.y, width: size, height: size * dice.range(1.0, 1.4))
        fill(CGPath(roundedRect: rect, cornerWidth: size * 0.08, cornerHeight: size * 0.08, transform: nil), alpha: 0.82, color: palette.accent)
        let inner = rect.insetBy(dx: size * 0.16, dy: size * 0.16)
        for _ in 0..<dice.int(5, 8) {
            let horizontal = dice.chance(0.5)
            let along = dice.range(0, 1)
            let from = dice.range(0, 0.4), to = dice.range(0.6, 1)
            let a = horizontal ? CGPoint(x: inner.minX + from * inner.width, y: inner.minY + along * inner.height)
                               : CGPoint(x: inner.minX + along * inner.width, y: inner.minY + from * inner.height)
            let b = horizontal ? CGPoint(x: inner.minX + to * inner.width, y: a.y)
                               : CGPoint(x: a.x, y: inner.minY + to * inner.height)
            pen([a, b], width: size * 0.07, alpha: 0.9, color: palette.paper)
        }
    }
}

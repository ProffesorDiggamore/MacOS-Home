import Foundation
import CoreGraphics
import CoreText

/// Pixel-art wallpapers: drawn small, dithered to two colours, then blown up with hard edges.
enum PixelScenes {
    /// 8×8 ordered-dither thresholds (0…1), the pattern classic Macs used for greys.
    private static let bayer: [Float] = {
        var matrix: [[Int]] = [[0, 2], [3, 1]]
        while matrix.count < 8 {
            let n = matrix.count
            var next = Array(repeating: Array(repeating: 0, count: n * 2), count: n * 2)
            for y in 0..<n {
                for x in 0..<n {
                    let v = 4 * matrix[y][x]
                    next[y][x] = v
                    next[y][x + n] = v + 2
                    next[y + n][x] = v + 3
                    next[y + n][x + n] = v + 1
                }
            }
            matrix = next
        }
        return matrix.flatMap { $0 }.map { (Float($0) + 0.5) / 64 }
    }()

    /// The pixel grid for a wallpaper about `rows` big pixels tall.
    private static func grid(width: Int, height: Int, rows: Int) -> (pixel: Int, columns: Int, rows: Int) {
        let pixel = max(1, Int((Double(height) / Double(rows)).rounded()))
        return (pixel, (width + pixel - 1) / pixel, (height + pixel - 1) / pixel)
    }

    /// Two-colour ordered dither of `values` (0 dark … 1 light), scaled up with hard pixel edges.
    private static func dither(_ values: [Float], columns: Int, rows: Int, pixel: Int, width: Int, height: Int, palette: InkPalette) -> CGImage? {
        let dark = palette.dark, light = palette.light
        let darkBytes = [UInt8(dark.r * 255), UInt8(dark.g * 255), UInt8(dark.b * 255)]
        let lightBytes = [UInt8(light.r * 255), UInt8(light.g * 255), UInt8(light.b * 255)]
        var bytes = [UInt8](repeating: 255, count: columns * rows * 4)
        for y in 0..<rows {
            for x in 0..<columns {
                let threshold = bayer[(y % 8) * 8 + x % 8]
                let source = values[y * columns + x] > threshold ? lightBytes : darkBytes
                let index = (y * columns + x) * 4
                bytes[index] = source[0]
                bytes[index + 1] = source[1]
                bytes[index + 2] = source[2]
            }
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let small = CGImage(width: columns, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: columns * 4,
                                  space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        let drawn = CGSize(width: columns * pixel, height: rows * pixel)
        context.draw(small, in: CGRect(x: 0, y: CGFloat(height) - drawn.height, width: drawn.width, height: drawn.height))
        return context.makeImage()
    }

    // MARK: - Pixel night

    static func night(width: Int, height: Int, palette: InkPalette, dice: Dice) -> CGImage? {
        let (pixel, columns, rows) = grid(width: width, height: height, rows: 200)
        let noise = Noise1D(dice)
        let (w, h) = (Float(columns), Float(rows))
        let horizon = Int(h * Float(dice.range(0.6, 0.7)))
        let moon = (x: w * Float(dice.range(0.15, 0.85)), y: h * Float(dice.range(0.14, 0.32)), r: h * Float(dice.range(0.065, 0.09)))
        let craters: [(x: Float, y: Float, r: Float)] = (0..<5).map { _ in
            (moon.x + moon.r * Float(dice.range(-0.6, 0.6)), moon.y + moon.r * Float(dice.range(-0.6, 0.6)), moon.r * Float(dice.range(0.12, 0.3)))
        }

        // Three ranges of hills, far to near; the nearest carries a line of pines.
        let ranges: [(base: Float, amp: Float, freq: CGFloat, shade: Float)] = [(0.06, 0.24, 2.2, 0.2), (0.03, 0.16, 3.5, 0.1), (0.0, 0.1, 5.5, 0)]
        var ridges: [[Int]] = ranges.map { range in
            let phase = dice.range(0, 400)
            return (0..<columns).map { x in
                let n = Float(noise.fbm(CGFloat(x) / CGFloat(columns) * range.freq + phase, octaves: 5))
                return horizon - Int(h * (range.base + range.amp * (n + 0.5)))
            }
        }
        var x = dice.int(0, 6)
        while x < columns {
            let tall = Int(h * Float(dice.range(0.035, 0.08)))
            let ground = ridges[2][x]
            for row in 0..<tall {
                // Three tiers, each widening toward its base.
                let half = Int(Float(row % max(1, tall / 3) + row / 2) * 0.45)
                for dx in -half...half where x + dx >= 0 && x + dx < columns {
                    ridges[2][x + dx] = min(ridges[2][x + dx], ground - tall + row)
                }
            }
            x += dice.int(3, 14)
        }

        var values = [Float](repeating: 0, count: columns * rows)
        for y in 0..<horizon {
            let fy = Float(y)
            for x in 0..<columns {
                let fx = Float(x)
                let along = fy / Float(horizon)
                // Mostly solid night with a glow toward the horizon and around the moon.
                var v: Float = 0.45 * pow(along, 3)
                let dx = fx - moon.x, dy = fy - moon.y
                let distance = (dx * dx + dy * dy).squareRoot()
                v += 0.28 * exp(-max(0, distance - moon.r) / (moon.r * 1.2))
                if distance < moon.r {
                    v = 1
                    for crater in craters where hypot(fx - crater.x, fy - crater.y) < crater.r { v = 0.62 }
                }
                // Each range gets a moonlit rim along its top edge so the silhouettes separate.
                if y >= ridges[2][x] { v = y - ridges[2][x] < 1 ? 0.45 : ranges[2].shade }
                else if y >= ridges[1][x] { v = y - ridges[1][x] < 1 ? 0.5 : ranges[1].shade }
                else if y >= ridges[0][x] { v = y - ridges[0][x] < 1 ? 0.55 : ranges[0].shade + 0.08 * (1 - along) }
                values[y * columns + x] = v
            }
        }
        // Stars, some with a sparkle.
        for _ in 0..<(columns * horizon / 220) {
            let x = dice.int(1, columns - 2), y = dice.int(1, Int(Float(horizon) * 0.75))
            guard values[y * columns + x] < 0.3, y < ridges[0][x] else { continue }
            values[y * columns + x] = 1
            if dice.chance(0.12) {
                for (ox, oy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { values[(y + oy) * columns + x + ox] = 0.8 }
            }
        }
        // The lake mirrors everything, broken up by ripples, with a path of moonlight.
        let phase = Float(dice.range(0, 10))
        for y in horizon..<rows {
            let depth = Float(y - horizon)
            let source = max(0, horizon - 1 - Int(depth * 1.1))
            let ripple = Int(2.2 * sin(Float(y) * 0.9 + phase))
            let dim: Float = 0.55 - 0.3 * depth / max(1, h - Float(horizon))
            let gap = dice.chance(0.3)
            let shimmer = Float(dice.range(0.6, 1.1))
            for x in 0..<columns {
                let sx = min(columns - 1, max(0, x + ripple))
                var v = values[source * columns + sx] * dim
                if gap { v *= 0.5 }
                // A broken column of moonlight on the water.
                let fromPath = abs(Float(x) - moon.x - Float(ripple)) / (moon.r * (0.35 + 0.025 * depth) * shimmer)
                if fromPath < 1, !gap { v = max(v, 0.9 - 0.6 * fromPath) }
                values[y * columns + x] = v
            }
        }
        return dither(values, columns: columns, rows: rows, pixel: pixel, width: width, height: height, palette: palette)
    }

    // MARK: - Dithered chrome

    private static let chromeScenes: [StudioScene] = [.liquidChrome, .liquidMetal, .satin, .chromeVeins]

    /// A studio render at low resolution, as 0…1 brightness, stretched to use the full range.
    private static func chromeBrightness(seed: Int, columns: Int, rows: Int, scenes: [StudioScene] = chromeScenes) -> [Float]? {
        let scene = scenes[abs(seed) % scenes.count]
        guard let image = StudioRenderer.render(scene, tone: .silver, seed: seed, width: columns, height: rows, quality: .preview),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        let bytes = data.bindMemory(to: UInt8.self, capacity: columns * rows * 4)
        let values = (0..<(columns * rows)).map { i -> Float in
            let r = Float(bytes[i * 4]), g = Float(bytes[i * 4 + 1]), b = Float(bytes[i * 4 + 2])
            return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        }
        let sorted = values.sorted()
        let low = sorted[sorted.count / 50], high = sorted[sorted.count - 1 - sorted.count / 50]
        let span = max(0.05, high - low)
        // Stretch to the full range, then a gentle S-curve for punchier highlights.
        return values.map { value in
            let v = max(0, min(1, (value - low) / span))
            return v * v * (3 - 2 * v)
        }
    }

    static func ditheredChrome(width: Int, height: Int, palette: InkPalette, seed: Int) -> CGImage? {
        let (pixel, columns, rows) = grid(width: width, height: height, rows: 220)
        guard var values = chromeBrightness(seed: seed, columns: columns, rows: rows) else { return nil }
        // Atkinson error diffusion, like photos in MacPaint.
        for y in 0..<rows {
            for x in 0..<columns {
                let index = y * columns + x
                let old = values[index]
                let new: Float = old > 0.5 ? 1 : 0
                values[index] = new
                let error = (old - new) / 8
                for (dx, dy) in [(1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)] {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, nx < columns, ny < rows { values[ny * columns + nx] += error }
                }
            }
        }
        return dither(values, columns: columns, rows: rows, pixel: pixel, width: width, height: height, palette: palette)
    }

    // MARK: - ASCII

    private static let ramp = Array(" .'`^\",:;Il!i~+_-?][}{1)(|/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$")

    static func ascii(width: Int, height: Int, palette: InkPalette, seed: Int) -> CGImage? {
        let lines = 72
        let cellHeight = CGFloat(height) / CGFloat(lines)
        let fontSize = cellHeight * 0.98
        let cellWidth = fontSize * 0.602 // Menlo's advance
        let columns = Int(CGFloat(width) / cellWidth) + 1
        // Sample the render at twice the character grid, with square pixels.
        let sampleWidth = columns * 2
        let sampleHeight = max(lines, Int(CGFloat(sampleWidth) * CGFloat(height) / CGFloat(width)))
        guard let values = chromeBrightness(seed: seed, columns: sampleWidth, rows: sampleHeight, scenes: [.liquidChrome, .liquidMetal, .chromeVeins]),
              let canvas = InkCanvas(width: width, height: height, palette: palette) else { return nil }

        let font = CTFontCreateWithName("Menlo-Regular" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): canvas.color(palette.ink, 0.92),
        ]
        let context = canvas.context
        context.saveGState()
        context.scaleBy(x: 1, y: -1) // Core Text wants y up
        context.translateBy(x: 0, y: -canvas.height)
        for line in 0..<lines {
            var text = ""
            text.reserveCapacity(columns)
            let y0 = line * sampleHeight / lines, y1 = max(y0 + 1, (line + 1) * sampleHeight / lines)
            for column in 0..<columns {
                let x0 = column * 2, x1 = min(sampleWidth, x0 + 2)
                var sum: Float = 0
                var count: Float = 0
                for y in y0..<min(y1, sampleHeight) {
                    for x in x0..<x1 {
                        sum += values[y * sampleWidth + x]
                        count += 1
                    }
                }
                let brightness = count > 0 ? sum / count : 0
                let ink = palette.isDark ? brightness : 1 - brightness
                text.append(ramp[min(ramp.count - 1, Int(ink * Float(ramp.count - 1) + 0.5))])
            }
            let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            context.textPosition = CGPoint(x: 0, y: canvas.height - CGFloat(line + 1) * cellHeight + cellHeight * 0.22)
            CTLineDraw(ctLine, context)
        }
        context.restoreGState()
        canvas.finish(seed: seed, grain: 5, vignette: 0.08)
        return canvas.image
    }
}

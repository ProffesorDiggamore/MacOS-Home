import Foundation
import CoreGraphics
import simd

/// Glitch art: a generated scene that's then corrupted the way broken video is — blocks,
/// smeared rows, dripping highlights and sorted pixels. Built at up to 1920–2560 pixels wide
/// and enlarged by a whole number with hard edges, so the corruption stays crisp at 4K and up.
enum GlitchScenes {
    // MARK: - Datamosh

    /// A mossy cliff with waterfalls and a wet black stone, cut into panels and broken up like a
    /// corrupted video frame: dragged rows, sorted columns, mosaic patches and drips into a dead strip.
    static func datamosh(width: Int, height: Int, tone: StudioTone, palette: InkPalette, seed: Int, dice: Dice) -> CGImage? {
        let (w, h) = Raster.workSize(width: width, height: height, maxWidth: 1920)
        let ramp = ColorRamp(stops: palette.ramp)
        let light = SIMD3<Float>(palette.light), dark = SIMD3<Float>(palette.dark), tint = SIMD3<Float>(palette.tint)
        let noise = Noise2D(seed: UInt32(dice.int(1, 1_000_000)))
        let u = Float(h) / 1000
        let wide = Float(w) / u

        // 1. Foliage height: clumps of leaves at three sizes, shaded as if lit from above.
        var relief = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let py = Float(y) / u
            for x in 0..<w {
                let px = Float(x) / u
                let clumps = noise.fbm(px * 0.012, py * 0.012, octaves: 4)
                let leaves = noise.fbm(px * 0.06 + 31, py * 0.06, octaves: 3)
                let fine = noise.value(px * 0.3, py * 0.3)
                relief[y * w + x] = clumps * 0.55 + leaves * 0.35 + fine * 0.1
            }
        }
        struct Fall { var x: Float; var width: Float; var top: Float; var phase: Float }
        let falls: [Fall] = (0..<dice.int(2, 3)).map { _ in
            Fall(x: Float(dice.range(0.1, 0.9)) * wide, width: Float(dice.range(20, 55)), top: Float(dice.range(-100, 300)), phase: Float(dice.range(0, 90)))
        }
        var base = Raster(width: w, height: h)
        for y in 0..<h {
            let py = Float(y) / u
            for x in 0..<w {
                let px = Float(x) / u
                let i = y * w + x
                let hv = relief[i]
                let slope = (relief[max(0, i - w - 1)] - relief[min(w * h - 1, i + w + 1)]) * 18
                let shade = max(0, min(1, 0.55 + slope))
                let hue = noise.value(px * 0.02 + 77, py * 0.02)
                var c = ramp(0.08 + 0.75 * hv * shade + 0.12 * shade)
                c = c.mixed(with: c * SIMD3(1.08, 1.05, 0.8), hue * 0.5) // warmer, yellower leaves here and there
                // Stone: banded grey rock where the big-scale noise is high.
                let stone = noise.fbm(px * 0.0035 + 50, py * 0.0035, octaves: 3)
                if stone > 0.6 {
                    let strata = noise.fbm(px * 0.05 + 7, py * 0.011, octaves: 3)
                    let carved = abs(sin(px * 0.09) * sin(py * 0.07)) > 0.7 ? Float(0.82) : 1
                    let rock = ramp(0.06 + 0.42 * strata * shade) * carved
                    c = c.mixed(with: SIMD3(repeating: rock.luminance).mixed(with: rock, 0.4), smoothstep(0.6, 0.64, stone))
                }
                for fall in falls where py > fall.top {
                    let wobble = (noise.value(py * 0.005, fall.phase) - 0.5) * fall.width * 1.4
                    let d = abs(px - fall.x - wobble) / fall.width
                    guard d < 2 else { continue }
                    let streak = noise.value(px * 0.45, py * 0.01 + fall.phase)
                    let core = max(0, 1 - d * d)
                    c = c.mixed(with: light * (0.7 + 0.3 * streak), core * (0.45 + 0.55 * streak))
                    let foam = smoothstep(0.55, 0.9, noise.fbm(px * 0.05, py * 0.05 + fall.phase, octaves: 3))
                    c = c.mixed(with: light * 0.92, max(0, 2 - d) / 2 * (0.25 + 0.5 * foam) * min(1, (py - fall.top) / 300))
                }
                base.set(x, y, c)
            }
        }

        // 2. A wet black stone in the middle: liquid chrome, blended in through a ragged mask.
        if let chrome = StudioRenderer.render(.liquidMetal, tone: tone, seed: seed, width: w, height: h, quality: w <= 1000 ? .thumbnail : .preview),
           let stone = Raster(image: chrome, width: w, height: h) {
            let center = SIMD2<Float>(Float(dice.range(0.3, 0.7)) * wide, Float(dice.range(350, 600)))
            let reach = SIMD2<Float>(Float(dice.range(160, 300)), Float(dice.range(220, 380)))
            for y in 0..<h {
                for x in 0..<w {
                    let p = SIMD2<Float>(Float(x) / u, Float(y) / u)
                    let d = simd_length((p - center) / reach)
                    let edge = 0.75 + 0.5 * noise.fbm(p.x * 0.01 + 90, p.y * 0.01, octaves: 3)
                    let amount = 1 - smoothstep(edge - 0.12, edge, d)
                    if amount > 0 { base.set(x, y, base.get(x, y).mixed(with: stone.get(x, y), amount)) }
                }
            }
        }

        var image = base
        // 3. Panels pulled from elsewhere in the frame: zoomed in, fogged, shifted or mirrored.
        for _ in 0..<dice.int(3, 5) {
            let rect = randomRect(w, h, dice, widths: (0.08, 0.26), heights: (0.3, 0.9))
            let kind = dice.int(0, 3)
            let (ox, oy) = (Float(dice.range(0, 1)) * Float(w), Float(dice.range(0, 1)) * Float(h) * 0.5)
            let lift = Float(dice.range(0.1, 0.3))
            for y in rect.minY..<rect.maxY {
                for x in rect.minX..<rect.maxX {
                    let lx = Float(x - rect.minX), ly = Float(y - rect.minY)
                    var c: SIMD3<Float>
                    switch kind {
                    case 0: c = base.sample(ox * 0.5 + lx * 0.45, oy + ly * 0.45).mixed(with: tint, lift)
                    case 1:
                        let fog = noise.fbm(Float(x) * 0.003, Float(y) * 0.012 + 40, octaves: 3)
                        c = base.get(x + Int(ox) / 3, y).mixed(with: light * 0.86, 0.5 + 0.4 * fog)
                    case 2: c = base.get(x + Int(ox * 0.3) - w / 6, y - Int(oy * 0.2))
                    default: c = base.get(rect.maxX - 1 - (x - rect.minX) + Int(ox * 0.2), y)
                    }
                    image.set(x, y, c)
                }
            }
        }

        // 4. Corruption.
        for _ in 0..<dice.int(5, 10) {
            macroblocks(&image, rect: randomRect(w, h, dice, widths: (0.04, 0.14), heights: (0.04, 0.14)),
                        block: max(4, Int(Float([8, 12, 16, 24][dice.int(0, 3)]) * Float(w) / 1920)))
        }
        for _ in 0..<dice.int(1, 3) {
            let rect = randomRect(w, h, dice, widths: (0.08, 0.2), heights: (0.15, 0.35))
            let cell = max(3, Int(Float(dice.range(5, 12)) * u))
            for y in rect.minY..<rect.maxY {
                for x in rect.minX..<rect.maxX { image.set(x, y, base.get(x - (x - rect.minX) % cell, y - (y - rect.minY) % cell)) }
            }
        }
        smearDown(&image, dice: dice, noise: noise, bands: dice.int(4, 7), u: u)
        for _ in 0..<dice.int(1, 3) {
            sortSpans(&image, rect: randomRect(w, h, dice, widths: (0.05, 0.16), heights: (0.4, 0.9)), vertical: true,
                      low: 0.35, high: 0.95, noise: noise)
        }
        sliceShift(&image, dice: dice, count: dice.int(3, 6), u: u)
        drips(&image, dice: dice, threshold: 0.7, chance: 0.015, maxLength: 160 * u)

        // 5. Pale speckled outlines where detail meets the dark.
        let snapshot = image
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let l = snapshot.luminance(x, y)
                guard l < 0.28 else { continue }
                let edge = abs(snapshot.luminance(x + 1, y) - l) + abs(snapshot.luminance(x, y + 1) - l)
                if edge > 0.14 { image.set(x, y, light * (0.7 + 0.3 * noise.value(Float(x) * 0.7, Float(y) * 0.7))) }
            }
        }

        // 6. A dead strip along the bottom, its top edge stepped in blocks, with the picture
        // dripping into it as pale outlines.
        let voidTop = Float(h) * Float(dice.range(0.8, 0.88))
        let step = max(6, Int(24 * u))
        var x = 0
        while x < w {
            let top = Int(voidTop + Float(dice.range(-60, 30)) * u)
            for y in max(0, top)..<h { for k in x..<min(w, x + step) { image.set(k, y, dark * 0.45) } }
            x += step
        }
        for _ in 0..<dice.int(0, 1) {
            let rect = randomRect(w, h, dice, widths: (0.03, 0.08), heights: (0.15, 0.3))
            for y in rect.minY..<rect.maxY { for x in rect.minX..<rect.maxX { image.set(x, y, dark * 0.45) } }
        }
        for _ in 0..<dice.int(26, 48) {
            let x = dice.int(0, w - 1)
            let thick = max(2, Int(Float(dice.range(3, 14)) * u))
            let start = Int(voidTop - Float(dice.range(0, 70)) * u)
            let length = Int(Float(dice.range(30, 190)) * u)
            let source = base.get(x, start)
            let outline = source.luminance > 0.45 ? source : light * 0.85
            for y in start..<min(h, start + length) {
                image.set(x, y, outline)
                image.set(x + thick, y, outline)
                if dice.chance(0.05) { for k in 0...thick { image.set(x + k, y, outline) } }
            }
            for k in 0...thick { image.set(x + k, min(h - 1, start + length), outline) }
        }
        return image.image(width: width, height: height, crisp: true)
    }

    // MARK: - Pixel sort

    /// Domain-warped noise (noise fed through noise, twice) with spans of pixels sorted by brightness.
    static func pixelSort(width: Int, height: Int, palette: InkPalette, dice: Dice) -> CGImage? {
        let (w, h) = Raster.workSize(width: width, height: height, maxWidth: 2560)
        let ramp = ColorRamp(stops: palette.ramp)
        let noise = Noise2D(seed: UInt32(dice.int(1, 1_000_000)))
        let scale = Float(dice.range(1.6, 3.2)) / Float(h)
        let warp = Float(dice.range(2.5, 4.5))
        var image = Raster(width: w, height: h)
        for y in 0..<h {
            for x in 0..<w {
                let px = Float(x) * scale, py = Float(y) * scale
                let qx = noise.fbm(px, py, octaves: 4), qy = noise.fbm(px + 5.2, py + 1.3, octaves: 4)
                let rx = noise.fbm(px + warp * qx + 1.7, py + warp * qy + 9.2, octaves: 4)
                let ry = noise.fbm(px + warp * qx + 8.3, py + warp * qy + 2.8, octaves: 4)
                let f = noise.fbm(px + warp * rx, py + warp * ry, octaves: 5)
                let t = smoothstep(0.25, 0.75, f) * 0.85 + qx * 0.15
                image.set(x, y, ramp(t))
            }
        }
        sortSpans(&image, rect: (0, 0, w, h), vertical: dice.chance(0.65), low: Float(dice.range(0.15, 0.3)),
                  high: Float(dice.range(0.7, 0.9)), noise: noise, reverse: dice.chance(0.5))
        return image.image(width: width, height: height, crisp: true)
    }

    // MARK: - Chrome melt

    /// A studio chrome render, then smeared, sliced and dripping.
    static func melt(width: Int, height: Int, tone: StudioTone, seed: Int, dice: Dice) -> CGImage? {
        let (w, h) = Raster.workSize(width: width, height: height, maxWidth: 2560)
        let scenes: [StudioScene] = [.liquidChrome, .chromeVeins, .liquidChrome, .liquidMetal]
        let quality: StudioRenderer.Quality = w <= 800 ? .thumbnail : w <= 1700 ? .preview : .final
        guard let render = StudioRenderer.render(scenes[abs(seed) % scenes.count], tone: tone, seed: seed, width: w, height: h, quality: quality),
              var image = Raster(image: render, width: w, height: h) else { return nil }
        let u = Float(h) / 1000
        let noise = Noise2D(seed: UInt32(dice.int(1, 1_000_000)))
        for _ in 0..<dice.int(3, 7) {
            macroblocks(&image, rect: randomRect(w, h, dice, widths: (0.05, 0.2), heights: (0.05, 0.2)),
                        block: max(4, Int(Float([8, 16, 24, 32][dice.int(0, 3)]) * Float(w) / 1920)))
        }
        smearDown(&image, dice: dice, noise: noise, bands: dice.int(6, 11), u: u)
        for _ in 0..<dice.int(2, 4) {
            sortSpans(&image, rect: randomRect(w, h, dice, widths: (0.06, 0.2), heights: (0.5, 1)), vertical: true,
                      low: 0.25, high: 0.98, noise: noise)
        }
        sliceShift(&image, dice: dice, count: dice.int(8, 14), u: u)
        drips(&image, dice: dice, threshold: 0.55, chance: 0.05, maxLength: 320 * u)
        // A few bands with the red channel slipped sideways.
        for _ in 0..<dice.int(2, 5) {
            let top = dice.int(0, h - 1), tall = Int(Float(dice.range(4, 40)) * u)
            let offset = Int(Float(dice.range(4, 18)) * u) * (dice.chance(0.5) ? 1 : -1)
            let copy = image
            for y in top..<min(h, top + tall) {
                for x in 0..<w {
                    var c = copy.get(x, y)
                    c.x = copy.get(x + offset, y).x
                    image.set(x, y, c)
                }
            }
        }
        return image.image(width: width, height: height, crisp: true)
    }

    // MARK: - Shared corruptions

    private static func randomRect(_ w: Int, _ h: Int, _ dice: Dice, widths: (CGFloat, CGFloat), heights: (CGFloat, CGFloat))
        -> (minX: Int, minY: Int, maxX: Int, maxY: Int) {
        let rw = Int(CGFloat(w) * dice.range(widths.0, widths.1)), rh = Int(CGFloat(h) * dice.range(heights.0, heights.1))
        let x = dice.int(0, max(0, w - rw)), y = dice.int(0, max(0, h - rh))
        return (x, y, min(w, x + rw), min(h, y + rh))
    }

    /// Each block flattened to its average plus a slope, like a broken JPEG.
    private static func macroblocks(_ image: inout Raster, rect: (minX: Int, minY: Int, maxX: Int, maxY: Int), block: Int) {
        var by = rect.minY
        while by < rect.maxY {
            var bx = rect.minX
            while bx < rect.maxX {
                let x1 = min(rect.maxX, bx + block), y1 = min(rect.maxY, by + block)
                let a = image.get(bx, by), b = image.get(x1 - 1, by), c = image.get(bx, y1 - 1)
                var mean = SIMD3<Float>.zero
                for y in by..<y1 { for x in bx..<x1 { mean += image.get(x, y) } }
                mean /= Float((x1 - bx) * (y1 - by))
                for y in by..<y1 {
                    for x in bx..<x1 {
                        let fx = Float(x - bx) / Float(block) - 0.5, fy = Float(y - by) / Float(block) - 0.5
                        image.set(x, y, mean + (b - a) * fx * 0.6 + (c - a) * fy * 0.6)
                    }
                }
                bx += block
            }
            by += block
        }
    }

    /// Within each column (or row) of the rect, runs of mid-bright pixels are sorted by brightness.
    private static func sortSpans(_ image: inout Raster, rect: (minX: Int, minY: Int, maxX: Int, maxY: Int), vertical: Bool,
                                  low: Float, high: Float, noise: Noise2D, reverse: Bool = false) {
        let lines = vertical ? rect.minX..<rect.maxX : rect.minY..<rect.maxY
        let span = vertical ? rect.minY..<rect.maxY : rect.minX..<rect.maxX
        for line in lines {
            let shift = noise.value(Float(line) * 0.05, 3.3) * 0.15
            var start = -1
            var run: [(Float, SIMD3<Float>)] = []
            for i in span.lowerBound...span.upperBound {
                let (x, y) = vertical ? (line, i) : (i, line)
                let inside = i < span.upperBound && {
                    let l = image.luminance(x, y)
                    return l > low + shift && l < high
                }()
                // Long spans are broken up so streaks vary in length.
                let limit = Int(Float(span.count) * (0.15 + noise.value(Float(line) * 0.02, Float(i) * 0.004)))
                if inside && run.count < limit {
                    if start < 0 { start = i }
                    run.append((image.luminance(x, y), image.get(x, y)))
                } else if start >= 0 {
                    run.sort { reverse ? $0.0 < $1.0 : $0.0 > $1.0 }
                    for (k, item) in run.enumerated() {
                        vertical ? image.set(line, start + k, item.1) : image.set(start + k, line, item.1)
                    }
                    start = inside ? i : -1
                    run = inside ? [(image.luminance(x, y), image.get(x, y))] : []
                }
            }
        }
    }

    /// Bands where one row is dragged down over everything below it, unevenly, like stuck video.
    private static func smearDown(_ image: inout Raster, dice: Dice, noise: Noise2D, bands: Int, u: Float) {
        for _ in 0..<bands {
            let rect = randomRect(image.width, image.height, dice, widths: (0.04, 0.2), heights: (0.15, 0.6))
            let phase = Float(dice.range(0, 100))
            for x in rect.minX..<rect.maxX {
                let source = image.get(x, rect.minY)
                let reach = Float(rect.maxY - rect.minY) * (0.3 + 0.7 * noise.value(Float(x) * 0.08, phase))
                let end = rect.minY + Int(reach)
                for y in rect.minY..<min(image.height, end) {
                    let fade = Float(y - rect.minY) / max(1, reach)
                    image.set(x, y, source.mixed(with: image.get(x, y), fade * fade * 0.8))
                }
            }
        }
    }

    /// Thin horizontal bands slid sideways.
    private static func sliceShift(_ image: inout Raster, dice: Dice, count: Int, u: Float) {
        for _ in 0..<count {
            let top = dice.int(0, image.height - 1)
            let tall = max(1, Int(Float(dice.range(2, 16)) * u))
            let offset = Int(Float(dice.range(10, 140)) * u) * (dice.chance(0.5) ? 1 : -1)
            let copy = image
            for y in top..<min(image.height, top + tall) {
                for x in 0..<image.width { image.set(x, y, copy.get((x + offset + image.width) % image.width, y)) }
            }
        }
    }

    /// Bright pixels that bleed straight down, fading as they go.
    private static func drips(_ image: inout Raster, dice: Dice, threshold: Float, chance: CGFloat, maxLength: Float) {
        for x in 0..<image.width where dice.chance(0.5) {
            var y = 0
            while y < image.height {
                let c = image.get(x, y)
                if c.luminance > threshold && dice.chance(chance) {
                    let length = Int(Float(dice.range(0.15, 1)) * maxLength)
                    for k in 1..<max(2, length) where y + k < image.height {
                        let fade = Float(k) / Float(length)
                        image.set(x, y + k, c.mixed(with: image.get(x, y + k), fade))
                    }
                    y += length
                }
                y += 1
            }
        }
    }
}

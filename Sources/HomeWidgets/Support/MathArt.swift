import AppKit
import simd

/// Wallpapers computed pixel by pixel from complex maths: fractals, complex
/// functions, strange attractors and wave interference. Every pattern is a pure
/// function of (pattern, palette, seed), so a 300-pixel preview and an 8K render
/// of the same seed show the same picture — just sharper.
enum MathPattern: String, CaseIterable, Identifiable {
    case julia, mandelbrot, newton, domain, attractor, quasicrystal, lyapunov

    var id: String { rawValue }

    var label: String {
        switch self {
        case .julia: return "Julia Set"
        case .mandelbrot: return "Mandelbrot Zoom"
        case .newton: return "Newton Fractal"
        case .domain: return "Complex Function"
        case .attractor: return "Strange Attractor"
        case .quasicrystal: return "Quasicrystal"
        case .lyapunov: return "Lyapunov"
        }
    }

    var summary: String {
        switch self {
        case .julia: return "z → z² + c, coloured by escape speed and distance to the set"
        case .mandelbrot: return "Deep zooms into the Mandelbrot set's spirals and seahorses"
        case .newton: return "Which root Newton's method falls into, for a random polynomial"
        case .domain: return "Domain colouring of a rational function: hue = angle, bands = size"
        case .attractor: return "Clifford attractor: tens of millions of points of a chaotic orbit"
        case .quasicrystal: return "Interfering plane waves with 5-, 7- or 9-fold symmetry"
        case .lyapunov: return "Order and chaos in the logistic map, Markus–Lyapunov style"
        }
    }
}

/// Smooth colour ramp built from a palette's accent colours, looked up by 0…1 (wraps).
struct ColorRamp {
    let stops: [SIMD3<Float>]
    let dark: SIMD3<Float>
    let deep: SIMD3<Float>

    init(_ palette: ArtPalette) {
        func rgb(_ hex: UInt32) -> SIMD3<Float> {
            SIMD3(Float((hex >> 16) & 255) / 255, Float((hex >> 8) & 255) / 255, Float(hex & 255) / 255)
        }
        let colors = palette.colors.map(rgb)
        deep = colors[0]
        dark = colors[1]
        let accents = Array(colors.dropFirst(2))
        stops = accents + [accents[0]] // cyclic
    }

    func color(_ t: Float) -> SIMD3<Float> {
        var u: Float = t - floor(t)
        u *= Float(stops.count - 1)
        let i = min(stops.count - 2, Int(u))
        let f: Float = u - Float(i)
        let smooth: Float = f * f * (3 - 2 * f)
        return simd_mix(stops[i], stops[i + 1], SIMD3(repeating: smooth))
    }
}

enum MathArt {
    /// Renders a pattern. Heavy: call off the main thread. `progress` gets 0…1.
    static func render(_ pattern: MathPattern, palette: ArtPalette, seed: Int, width: Int, height: Int,
                       progress: ((Double) -> Void)? = nil) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let ramp = ColorRamp(palette)
        var pixels = [UInt32](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBufferPointer { buffer in
            let out = buffer.baseAddress!
            switch pattern {
            case .attractor:
                Attractor.render(into: out, width: width, height: height, seed: seed, ramp: ramp, progress: progress)
            default:
                let shader = makeShader(pattern, seed: seed, width: width, height: height, ramp: ramp)
                perPixel(into: out, width: width, height: height, progress: progress, shader: shader)
            }
        }
        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func pack(_ c: SIMD3<Float>) -> UInt32 {
        let v = simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1)) * 255
        let r = UInt32(v.x + 0.5), g = UInt32(v.y + 0.5), b = UInt32(v.z + 0.5)
        return r | (g << 8) | (b << 16) | (255 << 24) // RGBX little-endian
    }

    /// Runs `shader` for every pixel, spread across all cores in bands of rows.
    static func perPixel(into out: UnsafeMutablePointer<UInt32>, width: Int, height: Int,
                         progress: ((Double) -> Void)?, shader: (Double, Double) -> SIMD3<Float>) {
        let band = 8
        let bands = (height + band - 1) / band
        let lock = NSLock()
        var done = 0
        DispatchQueue.concurrentPerform(iterations: bands) { b in
            let y0 = b * band, y1 = min(height, y0 + band)
            for y in y0..<y1 {
                let row = out + y * width
                for x in 0..<width {
                    row[x] = pack(shader(Double(x), Double(y)))
                }
            }
            lock.lock()
            done += 1
            let fraction = Double(done) / Double(bands)
            lock.unlock()
            if b % 16 == 0 { progress?(fraction) }
        }
        progress?(1)
    }

    /// Pixel → complex plane, keeping squares square and rotating the view.
    struct Plane {
        let cx: Double, cy: Double, span: Double, cosA: Double, sinA: Double, w: Double, h: Double
        init(cx: Double, cy: Double, span: Double, angle: Double, width: Int, height: Int) {
            self.cx = cx; self.cy = cy; self.span = span
            cosA = cos(angle); sinA = sin(angle)
            w = Double(width); h = Double(height)
        }
        var pixel: Double { span / h }
        func point(_ x: Double, _ y: Double) -> (Double, Double) {
            let u: Double = (x - w / 2) / h * span
            let v: Double = (h / 2 - y) / h * span
            let px: Double = cx + u * cosA - v * sinA
            let py: Double = cy + u * sinA + v * cosA
            return (px, py)
        }
    }

    static func makeShader(_ pattern: MathPattern, seed: Int, width: Int, height: Int, ramp: ColorRamp) -> (Double, Double) -> SIMD3<Float> {
        var rng = ArtRandom(seed &* 7919 &+ pattern.rawValue.count)
        switch pattern {
        case .julia: return julia(&rng, width, height, ramp)
        case .mandelbrot: return mandelbrot(&rng, width, height, ramp)
        case .newton: return newton(&rng, width, height, ramp)
        case .domain: return domain(&rng, width, height, ramp)
        case .quasicrystal: return quasicrystal(&rng, width, height, ramp)
        case .lyapunov: return lyapunov(&rng, width, height, ramp)
        case .attractor: return { _, _ in ramp.deep }
        }
    }

    // MARK: Julia

    static func julia(_ rng: inout ArtRandom, _ width: Int, _ height: Int, _ ramp: ColorRamp) -> (Double, Double) -> SIMD3<Float> {
        let angle: Double = rng.range(0, .pi * 2)
        let radius: Double = 0.7885 + rng.range(-0.012, 0.012)
        let c = (radius * cos(angle), radius * sin(angle))
        let plane = Plane(cx: rng.range(-0.08, 0.08), cy: rng.range(-0.06, 0.06), span: rng.range(1.15, 1.7),
                          angle: rng.range(0, .pi * 2), width: width, height: height)
        let phase = Float(rng.range(0, 1))
        let maxIter = 400
        return { x, y in
            var (zx, zy) = plane.point(x, y)
            var dx = 1.0, dy = 0.0
            var i = 0
            var r2 = zx * zx + zy * zy
            while i < maxIter && r2 < 1e6 {
                let ndx: Double = 2 * (zx * dx - zy * dy)
                let ndy: Double = 2 * (zx * dy + zy * dx)
                dx = ndx; dy = ndy
                let nx: Double = zx * zx - zy * zy + c.0
                zy = 2 * zx * zy + c.1
                zx = nx
                r2 = zx * zx + zy * zy
                i += 1
            }
            if i == maxIter {
                let t = Float(min(1, sqrt(r2)))
                return simd_mix(ramp.deep, ramp.dark, SIMD3(repeating: t * 0.6))
            }
            return escapeColor(i: i, r2: r2, dx: dx, dy: dy, pixel: plane.pixel, phase: phase, density: 0.045, ramp: ramp)
        }
    }

    /// Shared colouring for escape-time fractals: smooth iteration count picks the hue;
    /// the distance estimate brightens fine filaments near the set.
    static func escapeColor(i: Int, r2: Double, dx: Double, dy: Double, pixel: Double, phase: Float, density: Float,
                            ramp: ColorRamp) -> SIMD3<Float> {
        let modulus: Double = sqrt(r2)
        let logMod: Double = log(modulus)
        let nu: Double = Double(i) + 1 - log2(max(1e-9, logMod))
        let derivative: Double = max(1e-12, sqrt(dx * dx + dy * dy))
        let distance: Double = modulus * logMod / derivative
        let ratio = Float(distance / pixel)
        let glow: Float = 0.3 + 0.7 * exp(-ratio * 0.08)
        let t: Float = Float(sqrt(max(0, nu))) * density * 4 + phase
        let base = ramp.color(t)
        let fade: Float = min(1, Float(nu) / 6)
        return simd_mix(ramp.deep, base * glow, SIMD3(repeating: fade))
    }

    // MARK: Mandelbrot

    static let mandelbrotSpots: [(Double, Double, Double)] = [
        (-0.743643887037151, 0.131825904205330, 0.0032),
        (-0.745428, 0.113009, 0.0042),
        (-0.7453, 0.1127, 0.0065),
        (-1.25066, 0.02012, 0.00035),
        (-0.10109636384562, 0.95628651080914, 0.00012),
        (-0.77568377, 0.13646737, 0.0005),
        (-0.088, 0.654, 0.04),
        (-1.7497591451303, 0.0000000036, 0.000006),
        (0.3750001200618655, -0.2166393884377127, 0.0004),
        (-0.1592, -1.0317, 0.03),
    ]

    static func mandelbrot(_ rng: inout ArtRandom, _ width: Int, _ height: Int, _ ramp: ColorRamp) -> (Double, Double) -> SIMD3<Float> {
        let start = Int(rng.range(0, Double(mandelbrotSpots.count)))
        let angle: Double = rng.range(0, .pi * 2)
        let phase = Float(rng.range(0, 1))
        var chosen = mandelbrotSpots[start]
        var maxIter = 600
        // Keep the first spot (with a little jitter) whose sample mixes inside and outside.
        for k in 0..<mandelbrotSpots.count {
            let spot = mandelbrotSpots[(start + k) % mandelbrotSpots.count]
            let jitterX: Double = rng.range(-0.25, 0.25) * spot.2
            let jitterY: Double = rng.range(-0.25, 0.25) * spot.2
            let span: Double = spot.2 * rng.range(0.7, 1.3)
            let iterations = Int(min(3000, 300 + 220 * max(0, -log10(span))))
            let plane = Plane(cx: spot.0 + jitterX, cy: spot.1 + jitterY, span: span, angle: angle, width: 64, height: 36)
            var escaped = 0
            for sy in 0..<36 {
                for sx in 0..<64 {
                    let (px, py) = plane.point(Double(sx), Double(sy))
                    if mandelIter(px, py, iterations).0 < iterations { escaped += 1 }
                }
            }
            let share = Double(escaped) / Double(64 * 36)
            if share > 0.35 && share < 0.985 {
                chosen = (spot.0 + jitterX, spot.1 + jitterY, span)
                maxIter = iterations
                break
            }
        }
        let plane = Plane(cx: chosen.0, cy: chosen.1, span: chosen.2, angle: angle, width: width, height: height)
        return { x, y in
            let (px, py) = plane.point(x, y)
            let (i, zx, zy, dx, dy) = mandelIter(px, py, maxIter)
            if i == maxIter { return ramp.deep }
            return escapeColor(i: i, r2: zx * zx + zy * zy, dx: dx, dy: dy, pixel: plane.pixel, phase: phase, density: 0.03, ramp: ramp)
        }
    }

    static func mandelIter(_ cx: Double, _ cy: Double, _ maxIter: Int) -> (Int, Double, Double, Double, Double) {
        var zx = 0.0, zy = 0.0, dx = 0.0, dy = 0.0
        var i = 0
        while i < maxIter {
            let r2: Double = zx * zx + zy * zy
            if r2 > 1e6 { break }
            let ndx: Double = 2 * (zx * dx - zy * dy) + 1
            let ndy: Double = 2 * (zx * dy + zy * dx)
            dx = ndx; dy = ndy
            let nx: Double = zx * zx - zy * zy + cx
            zy = 2 * zx * zy + cy
            zx = nx
            i += 1
        }
        return (i, zx, zy, dx, dy)
    }

    // MARK: Newton

    static func newton(_ rng: inout ArtRandom, _ width: Int, _ height: Int, _ ramp: ColorRamp) -> (Double, Double) -> SIMD3<Float> {
        let count = Int(rng.range(3, 7.99))
        var roots: [(Double, Double)] = []
        while roots.count < count {
            let r: Double = rng.range(0.35, 1.0)
            let a: Double = rng.range(0, .pi * 2)
            let p = (r * cos(a), r * sin(a))
            if roots.allSatisfy({ hypot($0.0 - p.0, $0.1 - p.1) > 0.4 }) { roots.append(p) }
        }
        let relax: Double = rng.range(1.0, 1.45) // > 1 twists the basins into spirals
        let plane = Plane(cx: 0, cy: 0, span: rng.range(2.2, 3.4), angle: rng.range(0, .pi * 2), width: width, height: height)
        let colors: [SIMD3<Float>] = (0..<count).map { ramp.color(Float($0) / Float(count)) }
        let maxIter = 60
        return { x, y in
            var (zx, zy) = plane.point(x, y)
            for i in 0..<maxIter {
                var sx = 0.0, sy = 0.0
                for (k, root) in roots.enumerated() {
                    let ux: Double = zx - root.0, uy: Double = zy - root.1
                    let d2: Double = ux * ux + uy * uy
                    if d2 < 1e-7 {
                        let shade = Float(pow(0.93, Double(i)))
                        let rim: Float = 0.25 + 0.75 * shade
                        return simd_mix(ramp.deep, colors[k], SIMD3(repeating: rim))
                    }
                    sx += ux / d2
                    sy -= uy / d2
                }
                let s2: Double = sx * sx + sy * sy
                if s2 < 1e-24 { break }
                zx -= relax * sx / s2
                zy += relax * sy / s2
            }
            return ramp.deep
        }
    }

    // MARK: Domain colouring

    static func domain(_ rng: inout ArtRandom, _ width: Int, _ height: Int, _ ramp: ColorRamp) -> (Double, Double) -> SIMD3<Float> {
        func randomPoints(_ n: Int, _ rng: inout ArtRandom) -> [(Double, Double)] {
            (0..<n).map { _ in (rng.range(-1.4, 1.4), rng.range(-0.9, 0.9)) }
        }
        let zeros = randomPoints(Int(rng.range(2, 4.99)), &rng)
        let poles = randomPoints(Int(rng.range(1, 3.99)), &rng)
        let twist: Double = rng.range(0, .pi * 2)
        let rings: Double = rng.range(0.8, 1.6)
        let spokes: Double = Double(Int(rng.range(6, 16)))
        let plane = Plane(cx: 0, cy: 0, span: rng.range(2.6, 3.6), angle: rng.range(-0.4, 0.4), width: width, height: height)
        return { x, y in
            let (zx, zy) = plane.point(x, y)
            var logMag = 0.0, arg = twist
            for z in zeros {
                let ux: Double = zx - z.0, uy: Double = zy - z.1
                logMag += 0.5 * log(max(1e-30, ux * ux + uy * uy))
                arg += atan2(uy, ux)
            }
            for p in poles {
                let ux: Double = zx - p.0, uy: Double = zy - p.1
                logMag -= 0.5 * log(max(1e-30, ux * ux + uy * uy))
                arg -= atan2(uy, ux)
            }
            let hue = Float(arg / (2 * .pi))
            let band: Double = (logMag * rings / log(2.0)).truncatingRemainder(dividingBy: 1)
            let bandUp: Double = band < 0 ? band + 1 : band
            let contour = Float(0.62 + 0.38 * pow(bandUp, 0.55))
            let spoke: Double = (Double(hue) * spokes).truncatingRemainder(dividingBy: 1)
            let spokeUp: Double = spoke < 0 ? spoke + 1 : spoke
            let line = Float(0.88 + 0.12 * min(1, abs(spokeUp - 0.5) * 6))
            let lift = Float(1 / (1 + exp(-logMag * 0.6))) // dark near zeros, bright near poles
            let base = ramp.color(hue)
            let lit = simd_mix(ramp.deep, base, SIMD3(repeating: 0.35 + 0.65 * lift))
            return lit * contour * line
        }
    }

    // MARK: Quasicrystal

    static func quasicrystal(_ rng: inout ArtRandom, _ width: Int, _ height: Int, _ ramp: ColorRamp) -> (Double, Double) -> SIMD3<Float> {
        let folds = [5, 7, 9, 11][Int(rng.range(0, 3.99))]
        let wavelength: Double = Double(height) / rng.range(14, 34)
        let k: Double = 2 * .pi / wavelength
        let stripes: Double = rng.range(1.5, 3.5)
        let phase: Double = rng.range(0, .pi * 2)
        let cx: Double = Double(width) * rng.range(0.3, 0.7), cy: Double = Double(height) * rng.range(0.3, 0.7)
        let dirs: [(Double, Double)] = (0..<folds).map { i in
            let a: Double = Double(i) * .pi / Double(folds) + phase
            return (cos(a), sin(a))
        }
        return { x, y in
            let px: Double = x - cx, py: Double = y - cy
            var sum = 0.0
            for d in dirs { sum += cos(k * (px * d.0 + py * d.1) + phase) }
            let v: Double = (sum / Double(folds) + 1) / 2
            // Fold the value back on itself for crisp interference stripes.
            let folded: Double = v * stripes
            let f: Double = folded - floor(folded)
            let tri: Double = Int(floor(folded)) % 2 == 0 ? f : 1 - f
            let t = Float(tri)
            let base = ramp.color(t * 0.8 + Float(phase / (2 * .pi)))
            let shade: Float = 0.25 + 0.75 * Float(v)
            return simd_mix(ramp.deep, base, SIMD3(repeating: shade))
        }
    }

    // MARK: Lyapunov

    /// (sequence, a range, b range) — the classic, well-known beautiful regions.
    static let lyapunovRegions: [(String, ClosedRange<Double>, ClosedRange<Double>)] = [
        ("BBBBBBAAAAAA", 3.4...4.0, 2.5...3.4),   // "Zircon Zity"
        ("AB", 2.0...4.0, 2.0...4.0),
        ("AABAB", 3.0...4.0, 3.0...4.0),
        ("AABB", 2.6...4.0, 2.6...4.0),
        ("ABBBA", 2.8...4.0, 2.8...4.0),
        ("BBABA", 3.2...4.0, 2.6...3.8),
    ]

    static func lyapunov(_ rng: inout ArtRandom, _ width: Int, _ height: Int, _ ramp: ColorRamp) -> (Double, Double) -> SIMD3<Float> {
        let region = lyapunovRegions[Int(rng.range(0, Double(lyapunovRegions.count) - 0.01))]
        let sequence = Array(region.0).map { $0 == "A" }
        let zoom: Double = rng.range(0.75, 1.0)
        let fullA: Double = region.1.upperBound - region.1.lowerBound
        let fullB: Double = region.2.upperBound - region.2.lowerBound
        let spanA: Double = fullA * zoom
        let spanB: Double = min(fullB, spanA * Double(height) / Double(width) * 1.4)
        let a0: Double = region.1.lowerBound + rng.range(0, fullA - spanA)
        let b0: Double = region.2.lowerBound + rng.range(0, max(0, fullB - spanB))
        let swap = rng.range(0, 1) > 0.5
        let w = Double(width), h = Double(height)
        let warm = 60, measure = 160
        return { x, y in
            let u: Double = x / w, v0: Double = 1 - y / h
            let ra: Double = a0 + (swap ? v0 : u) * spanA
            let rb: Double = b0 + (swap ? u : v0) * spanB
            var v = 0.5
            var step = 0
            for _ in 0..<warm {
                let r: Double = sequence[step % sequence.count] ? ra : rb
                v = r * v * (1 - v)
                step += 1
            }
            var total = 0.0, product = 1.0
            for i in 0..<measure {
                let r: Double = sequence[step % sequence.count] ? ra : rb
                v = r * v * (1 - v)
                product *= max(1e-12, abs(r * (1 - 2 * v)))
                step += 1
                if i % 6 == 5 {
                    total += log(product)
                    product = 1
                }
            }
            total += log(product)
            let lambda = Float(total / Double(measure))
            if lambda < 0 {
                let t: Float = min(1, -lambda / 1.4)
                let base = ramp.color(0.15 + t * 0.7)
                return simd_mix(ramp.dark, base, SIMD3(repeating: pow(t, 0.6)))
            }
            let chaos: Float = min(1, lambda * 1.5)
            return simd_mix(ramp.dark, ramp.deep, SIMD3(repeating: chaos))
        }
    }
}

// MARK: - Strange attractor

/// Clifford attractor: x' = sin(a·y) + c·cos(a·x), y' = sin(b·x) + d·cos(b·y).
/// Tens of millions of points are binned into a density map, then tone-mapped.
enum Attractor {
    static func parameters(seed: Int) -> (Double, Double, Double, Double, (Double, Double, Double, Double)) {
        var rng = ArtRandom(seed &* 104_729 &+ 11)
        for _ in 0..<60 {
            let a: Double = rng.range(-2, 2), b: Double = rng.range(-2, 2)
            let c: Double = rng.range(-1.6, 1.6), d: Double = rng.range(-1.6, 1.6)
            // Reject boring orbits (a point, a loop): the cloud must fill a good part of a grid.
            var x = 0.1, y = 0.1
            var minX = Double.infinity, maxX = -Double.infinity, minY = Double.infinity, maxY = -Double.infinity
            var cells = Set<Int>()
            for i in 0..<40_000 {
                let nx: Double = sin(a * y) + c * cos(a * x)
                let ny: Double = sin(b * x) + d * cos(b * y)
                x = nx; y = ny
                if i < 100 { continue }
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                cells.insert(Int((x + 3) * 20) * 1000 + Int((y + 3) * 20))
            }
            let area = (maxX - minX) * (maxY - minY)
            if cells.count > 900 && area > 1 { return (a, b, c, d, (minX, maxX, minY, maxY)) }
        }
        return (-1.4, 1.6, 1.0, 0.7, (-2.1, 2.1, -1.8, 1.8))
    }

    static func render(into out: UnsafeMutablePointer<UInt32>, width: Int, height: Int, seed: Int, ramp: ColorRamp,
                       progress: ((Double) -> Void)?) {
        let (a, b, c, d, raw) = parameters(seed: seed)
        // Tall attractors are turned sideways so they fill a wide screen.
        let sideways = (raw.3 - raw.2) > (raw.1 - raw.0) * 1.1 && width > height
        let bounds = sideways ? (raw.2, raw.3, raw.0, raw.1) : raw
        let rangeX = bounds.1 - bounds.0, rangeY = bounds.3 - bounds.2
        let scale: Double = min(Double(width) / rangeX, Double(height) / rangeY) * 0.94
        let offsetX: Double = (Double(width) - rangeX * scale) / 2 - bounds.0 * scale
        let offsetY: Double = (Double(height) - rangeY * scale) / 2 - bounds.2 * scale
        let threads = 4
        let perThread = width * height * 5 / threads
        let count = width * height
        var maps = [[UInt16]](repeating: [], count: threads)
        let lock = NSLock()
        var finished = 0
        DispatchQueue.concurrentPerform(iterations: threads) { t in
            var map = [UInt16](repeating: 0, count: count)
            var x = 0.1 + Double(t) * 0.013, y = -0.1 + Double(t) * 0.007
            map.withUnsafeMutableBufferPointer { bins in
                for i in 0..<perThread {
                    let nx: Double = sin(a * y) + c * cos(a * x)
                    let ny: Double = sin(b * x) + d * cos(b * y)
                    x = nx; y = ny
                    if i < 100 { continue }
                    let sx: Double = sideways ? y : x, sy: Double = sideways ? x : y
                    let px = Int(sx * scale + offsetX), py = Int(Double(height) - (sy * scale + offsetY))
                    if px >= 0 && px < width && py >= 0 && py < height {
                        let index = py * width + px
                        if bins[index] < UInt16.max { bins[index] += 1 }
                    }
                    if i % 4_000_000 == 0 {
                        lock.lock(); let f = (Double(finished) + Double(i) / Double(perThread)) / Double(threads); lock.unlock()
                        progress?(f * 0.9)
                    }
                }
            }
            lock.lock()
            maps[t] = map
            finished += 1
            lock.unlock()
        }
        var peak: UInt32 = 1
        var total = [UInt32](repeating: 0, count: count)
        for map in maps {
            for i in 0..<count { total[i] += UInt32(map[i]) }
        }
        for v in total where v > peak { peak = v }
        let logPeak = log(Float(peak) + 1)
        DispatchQueue.concurrentPerform(iterations: height) { y in
            for x in 0..<width {
                let i = y * width + x
                let v: Float = log(Float(total[i]) + 1) / logPeak
                if v <= 0 {
                    let edge = Float(y) / Float(height)
                    out[i] = MathArt.pack(simd_mix(ramp.deep, ramp.dark, SIMD3(repeating: edge * 0.5)))
                    continue
                }
                let base = ramp.color(0.08 + v * 0.85)
                var colour = simd_mix(ramp.deep, base, SIMD3(repeating: min(1, v * 1.6)))
                colour += SIMD3(repeating: pow(v, 4) * 0.35)
                out[i] = MathArt.pack(colour)
            }
        }
        progress?(1)
    }
}

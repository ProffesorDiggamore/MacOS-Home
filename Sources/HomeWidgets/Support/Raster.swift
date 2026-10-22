import Foundation
import CoreGraphics

/// An RGB pixel buffer (8 bits per channel, row 0 at the top) for wallpapers built pixel by pixel:
/// glitches, pixel sorting, refraction and attractor density plots.
struct Raster {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, fill: SIMD3<Float> = .zero) {
        self.width = width
        self.height = height
        let r = Raster.byte(fill.x), g = Raster.byte(fill.y), b = Raster.byte(fill.z)
        var row = [UInt8](repeating: 255, count: width * 4)
        for x in 0..<width {
            row[x * 4] = r
            row[x * 4 + 1] = g
            row[x * 4 + 2] = b
        }
        var all: [UInt8] = []
        all.reserveCapacity(width * height * 4)
        for _ in 0..<height { all += row }
        bytes = all
    }

    /// The image drawn (scaled) into a new buffer.
    init?(image: CGImage, width: Int, height: Int) {
        self.init(width: width, height: height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        if !drawn { return nil }
    }

    @inline(__always) static func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v * 255 + 0.5))) }

    @inline(__always) func get(_ x: Int, _ y: Int) -> SIMD3<Float> {
        let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
        let i = (cy * width + cx) * 4
        return SIMD3(Float(bytes[i]), Float(bytes[i + 1]), Float(bytes[i + 2])) / 255
    }

    @inline(__always) mutating func set(_ x: Int, _ y: Int, _ c: SIMD3<Float>) {
        guard x >= 0, y >= 0, x < width, y < height else { return }
        let i = (y * width + x) * 4
        bytes[i] = Raster.byte(c.x)
        bytes[i + 1] = Raster.byte(c.y)
        bytes[i + 2] = Raster.byte(c.z)
    }

    /// Bilinear sample at a fractional position (clamped to the edges).
    func sample(_ x: Float, _ y: Float) -> SIMD3<Float> {
        let fx = floor(x), fy = floor(y)
        let ix = Int(fx), iy = Int(fy)
        let tx = x - fx, ty = y - fy
        let top = get(ix, iy) * (1 - tx) + get(ix + 1, iy) * tx
        let bottom = get(ix, iy + 1) * (1 - tx) + get(ix + 1, iy + 1) * tx
        return top * (1 - ty) + bottom * ty
    }

    @inline(__always) func luminance(_ x: Int, _ y: Int) -> Float {
        let c = get(x, y)
        return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }

    func image() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Enlarged to the final size: hard pixel edges for glitch art, smooth otherwise.
    func image(width outWidth: Int, height outHeight: Int, crisp: Bool) -> CGImage? {
        guard let small = image() else { return nil }
        if outWidth == width && outHeight == height { return small }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: outWidth, height: outHeight, bitsPerComponent: 8, bytesPerRow: outWidth * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = crisp ? .none : .high
        // Keep whole pixels: scale by the same factor both ways and crop any spill at the edges.
        let scale = max(CGFloat(outWidth) / CGFloat(width), CGFloat(outHeight) / CGFloat(height))
        let drawn = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        context.draw(small, in: CGRect(x: 0, y: CGFloat(outHeight) - drawn.height, width: drawn.width, height: drawn.height))
        return context.makeImage()
    }

    /// The size to build glitch art at: the final size divided by a whole number, at most `maxWidth` wide.
    static func workSize(width: Int, height: Int, maxWidth: Int) -> (width: Int, height: Int) {
        let factor = max(1, Int((Double(width) / Double(maxWidth)).rounded(.up)))
        return ((width + factor - 1) / factor, (height + factor - 1) / factor)
    }
}

/// Maps 0…1 to a colour along evenly spaced stops.
struct ColorRamp {
    let stops: [SIMD3<Float>]

    func callAsFunction(_ t: Float) -> SIMD3<Float> {
        let x = max(0, min(1, t)) * Float(stops.count - 1)
        let i = min(stops.count - 2, Int(x))
        let f = x - Float(i)
        return stops[i] + (stops[i + 1] - stops[i]) * f
    }
}

/// Smooth 2D value noise in 0…1, seeded.
struct Noise2D {
    let seed: UInt32

    @inline(__always) private func hash(_ x: Int32, _ y: Int32) -> Float {
        var h = UInt32(bitPattern: x) &* 374_761_393 &+ UInt32(bitPattern: y) &* 668_265_263 &+ seed &* 2_246_822_519
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
    }

    func value(_ x: Float, _ y: Float) -> Float {
        let fx = floor(x), fy = floor(y)
        let ix = Int32(truncatingIfNeeded: Int(fx)), iy = Int32(truncatingIfNeeded: Int(fy))
        let tx = x - fx, ty = y - fy
        let sx: Float = tx * tx * (3 - 2 * tx)
        let sy: Float = ty * ty * (3 - 2 * ty)
        let a = hash(ix, iy), b = hash(ix &+ 1, iy), c = hash(ix, iy &+ 1), d = hash(ix &+ 1, iy &+ 1)
        let top: Float = a + (b - a) * sx
        let bottom: Float = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    /// Layered noise, roughly 0…1: big shapes with finer detail on top.
    func fbm(_ x: Float, _ y: Float, octaves: Int = 5) -> Float {
        var sum: Float = 0, amplitude: Float = 0.5, frequency: Float = 1, total: Float = 0
        for _ in 0..<octaves {
            sum += amplitude * value(x * frequency, y * frequency)
            total += amplitude
            frequency *= 2.02
            amplitude *= 0.5
        }
        return sum / total
    }
}

extension SIMD3 where Scalar == Float {
    init(_ rgb: InkPalette.RGB) { self.init(Float(rgb.r), Float(rgb.g), Float(rgb.b)) }

    var luminance: Float { 0.2126 * x + 0.7152 * y + 0.0722 * z }

    func mixed(with other: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { self + (other - self) * t }
}

@inline(__always) func smoothstep(_ a: Float, _ b: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
}

/// Seeded randomness with CGFloat helpers. A class so drawing helpers can share one stream.
final class Dice {
    private var random: ArtRandom
    init(_ seed: Int) { random = ArtRandom(seed) }
    func next() -> CGFloat { CGFloat(random.next()) }
    func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * next() }
    func int(_ a: Int, _ b: Int) -> Int { min(b, a + Int(next() * CGFloat(b - a + 1))) }
    func chance(_ p: CGFloat) -> Bool { next() < p }
    func sign() -> CGFloat { next() < 0.5 ? -1 : 1 }
    /// Roughly bell-shaped, mostly within ±1.
    func gauss() -> CGFloat { (next() + next() + next() - 1.5) / 0.75 }
}

/// Smooth 1D value noise in -1…1.
struct Noise1D {
    private let values: [CGFloat]
    init(_ dice: Dice, count: Int = 256) { values = (0..<count).map { _ in dice.next() * 2 - 1 } }

    func callAsFunction(_ x: CGFloat) -> CGFloat {
        let n = values.count
        let floorX = floor(x)
        let i = Int(floorX)
        let t = x - floorX
        let a = values[((i % n) + n) % n]
        let b = values[(((i + 1) % n) + n) % n]
        let s: CGFloat = t * t * (3 - 2 * t)
        return a + (b - a) * s
    }

    /// Layered noise: big shapes with smaller detail on top.
    func fbm(_ x: CGFloat, octaves: Int = 4) -> CGFloat {
        var sum: CGFloat = 0, amplitude: CGFloat = 0.5, frequency: CGFloat = 1
        for _ in 0..<octaves {
            sum += amplitude * self(x * frequency)
            frequency *= 2.03
            amplitude *= 0.5
        }
        return sum
    }
}

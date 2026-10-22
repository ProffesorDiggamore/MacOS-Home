import Foundation
import Metal
import CoreGraphics
import simd

/// What the wallpaper shows. The first four are surfaces seen from above; the rest are 3D objects.
enum StudioScene: String, CaseIterable, Identifiable {
    case liquidChrome, chromeVeins, satin, clay, glassRibbon, liquidMetal, darkGlass, glassPills

    var id: String { rawValue }
    var label: String {
        switch self {
        case .liquidChrome: return "Liquid Chrome"
        case .chromeVeins: return "Chrome Veins"
        case .satin: return "Satin"
        case .clay: return "Soft Layers"
        case .glassRibbon: return "Glass Ribbon"
        case .liquidMetal: return "Liquid Metal"
        case .darkGlass: return "Glass Sculpture"
        case .glassPills: return "Glass Pills"
        }
    }
    var summary: String {
        switch self {
        case .liquidChrome: return "Molten mirror metal swirling under studio lights"
        case .chromeVeins: return "Polished chrome tubes winding over gloss black"
        case .satin: return "Deep folds of glossy fabric"
        case .clay: return "Stacked soft terraces with real shadows"
        case .glassRibbon: return "A twisting glass band with true refraction"
        case .liquidMetal: return "Melted chrome forms reflecting each other"
        case .darkGlass: return "Thick flowing glass that bends the light"
        case .glassPills: return "Rows of smoked glass capsules"
        }
    }
    fileprivate var index: UInt32 { UInt32(Self.allCases.firstIndex(of: self) ?? 0) }
    fileprivate var isFlat: Bool { index < 4 }
    fileprivate var isGlass: Bool { self == .glassRibbon || self == .darkGlass || self == .glassPills }
}

/// The studio's colours: backdrop, lights and materials. Moss and Your Colors are built from three colours.
enum StudioTone: String, CaseIterable, Identifiable {
    case silver, obsidian, pearl, midnight, prism, moss, custom

    var id: String { rawValue }
    var label: String { self == .custom ? "Your Colors" : rawValue.capitalized }
    /// Two RRGGBB colours for the picker swatch.
    var swatch: (UInt32, UInt32) {
        switch self {
        case .silver: return (0xD9DBDF, 0x2A2C30)
        case .obsidian: return (0x3A3A3C, 0x050505)
        case .pearl: return (0xFFFFFF, 0xC9CBD0)
        case .midnight: return (0x6E8BD8, 0x070B1C)
        case .prism: return (0xE6E2F5, 0x3C3F4A)
        case .moss: return (0x8FAA62, 0x0B100B)
        case .custom:
            let colors = CustomTone.colors
            return (CustomTone.hex(colors.accent), CustomTone.hex(colors.background))
        }
    }
    /// The three colours behind Moss and Your Colors; nil for the hand-tuned neutral tones.
    var colors: CustomTone.Colors? {
        switch self {
        case .moss: return CustomTone.moss
        case .custom: return CustomTone.colors
        default: return nil
        }
    }
    /// Identifies the exact colours, so cached previews refresh when Your Colors change.
    var cacheKey: String {
        guard self == .custom else { return rawValue }
        let colors = CustomTone.colors
        return "custom-\(CustomTone.hex(colors.background))-\(CustomTone.hex(colors.ink))-\(CustomTone.hex(colors.accent))"
    }
}

/// The colours of the Your Colors tone: a background, an ink (lines, metal) and an accent.
/// Set from Settings › Wallpapers on the main thread, read by renders on background threads.
enum CustomTone {
    struct Colors: Equatable {
        var background: SIMD3<Float>
        var ink: SIMD3<Float>
        var accent: SIMD3<Float>

        var isDark: Bool { luminance(background) < 0.45 }
    }

    static let moss = Colors(background: SIMD3(0.045, 0.06, 0.045), ink: SIMD3(0.8, 0.82, 0.78), accent: SIMD3(0.45, 0.63, 0.24))
    static let standard = Colors(background: SIMD3(0.06, 0.06, 0.07), ink: SIMD3(0.9, 0.9, 0.9), accent: SIMD3(0.36, 0.55, 0.95))

    private static let lock = NSLock()
    private static var stored = standard
    static var colors: Colors {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }

    static func luminance(_ c: SIMD3<Float>) -> Float { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    static func hex(_ c: SIMD3<Float>) -> UInt32 {
        let r = UInt32(max(0, min(255, c.x * 255 + 0.5))), g = UInt32(max(0, min(255, c.y * 255 + 0.5))), b = UInt32(max(0, min(255, c.z * 255 + 0.5)))
        return r << 16 | g << 8 | b
    }

    static func color(hex: UInt32) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255)
    }
}

enum StudioRenderer {
    enum Quality { case thumbnail, preview, final }

    private struct Params {
        var width: UInt32, height: UInt32, originY: UInt32, scene: UInt32
        var samples: UInt32, pad0: UInt32 = 0, pad1: UInt32 = 0, pad2: UInt32 = 0
        var seed: SIMD4<Float>, seed2: SIMD4<Float>
        var skyTop: SIMD4<Float>, skyMid: SIMD4<Float>, skyBottom: SIMD4<Float>
        var metal: SIMD4<Float>, base: SIMD4<Float>, glass: SIMD4<Float>, misc: SIMD4<Float>
        var rot0: SIMD4<Float>, rot1: SIMD4<Float>, rot2: SIMD4<Float>, offset: SIMD4<Float>
        var sun: SIMD4<Float>
    }

    private struct Light {
        var dir: SIMD4<Float>, t1: SIMD4<Float>, t2: SIMD4<Float>, color: SIMD4<Float>, size: SIMD4<Float>
    }

    private struct GPU {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLComputePipelineState
    }

    private static let gpu: GPU? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: StudioShader.source, options: nil)
            guard let function = library.makeFunction(name: "studio") else { return nil }
            return GPU(device: device, queue: queue, pipeline: try device.makeComputePipelineState(function: function))
        } catch {
            fputs("Wallpaper shader failed: \(error)\n", stderr)
            return nil
        }
    }()

    /// Renders on the GPU in horizontal bands (so long renders never stall the display) and returns an sRGB image.
    static func render(_ scene: StudioScene, tone: StudioTone, seed: Int, width: Int, height: Int,
                       quality: Quality = .final, progress: ((Double) -> Void)? = nil) -> CGImage? {
        guard let gpu = Self.gpu, width > 0, height > 0 else { return nil }
        let length = width * height * 4
        guard let output = gpu.device.makeBuffer(length: length, options: .storageModeShared) else { return nil }

        var params = makeParams(scene, tone: tone, seed: seed, width: width, height: height, quality: quality)
        var lights = makeLights(tone: tone, seed: seed)
        var blobs = makeBlobs(seed: seed)

        let groupWidth = gpu.pipeline.threadExecutionWidth
        let groupHeight = max(1, min(8, gpu.pipeline.maxTotalThreadsPerThreadgroup / groupWidth))
        let budget = scene.isFlat ? 1_500_000 : 350_000
        let rowsPerBand = max(groupHeight, min(height, budget / width / groupHeight * groupHeight))
        var row = 0
        while row < height {
            let rows = min(rowsPerBand, height - row)
            params.originY = UInt32(row)
            guard let buffer = gpu.queue.makeCommandBuffer(), let encoder = buffer.makeComputeCommandEncoder() else { return nil }
            encoder.setComputePipelineState(gpu.pipeline)
            encoder.setBuffer(output, offset: 0, index: 0)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 1)
            lights.withUnsafeMutableBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 2) }
            blobs.withUnsafeMutableBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 3) }
            let groups = MTLSize(width: (width + groupWidth - 1) / groupWidth, height: (rows + groupHeight - 1) / groupHeight, depth: 1)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: MTLSize(width: groupWidth, height: groupHeight, depth: 1))
            encoder.endEncoding()
            buffer.commit()
            buffer.waitUntilCompleted()
            if buffer.status == .error { return nil }
            row += rows
            progress?(Double(row) / Double(height))
        }

        let data = Data(bytes: output.contents(), count: length)
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    // MARK: - Scene set-up

    private static func gray(_ v: Float) -> SIMD4<Float> { SIMD4(v, v, v, 0) }
    private static func rgb(_ r: Float, _ g: Float, _ b: Float, _ w: Float = 0) -> SIMD4<Float> { SIMD4(r, g, b, w) }

    private static func samples(_ scene: StudioScene, _ quality: Quality, pixels: Int) -> UInt32 {
        let big = pixels > 20_000_000
        switch quality {
        case .thumbnail: return scene.isGlass ? 3 : 1
        case .preview: return scene.isGlass ? 3 : 2
        case .final: return scene.isGlass ? (big ? 6 : 9) : (big ? 4 : 9)
        }
    }

    private static func makeParams(_ scene: StudioScene, tone: StudioTone, seed: Int, width: Int, height: Int, quality: Quality) -> Params {
        var rng = ArtRandom(seed &* 31 &+ Int(scene.index))
        func r() -> Float { Float(rng.next()) }
        let twists: [Float] = [0.5, 1.0, 1.5, 2.0]

        // Object orientation and framing.
        var angles = SIMD3<Float>(r() * 6.283, r() * 6.283, r() * 6.283)
        var offset = SIMD3<Float>(0, 0, 0)
        var distance: Float = 4.6
        switch scene {
        case .glassRibbon:
            angles = SIMD3(0.5 + r() * 0.8, r() * 6.283, (r() - 0.5) * 1.0)
            offset = SIMD3((r() - 0.5) * 1.2, (r() - 0.5) * 0.6, 0)
            distance = 4.4
        case .glassPills:
            angles = SIMD3((r() - 0.5) * 0.3, (r() - 0.5) * 0.6, (r() - 0.5) * 0.7)
            distance = 4.2
        default:
            offset = SIMD3((r() - 0.5) * 0.5, (r() - 0.5) * 0.3, 0)
            distance = 4.0
        }
        let rows = rotation(angles)

        var p = Params(width: UInt32(width), height: UInt32(height), originY: 0, scene: scene.index,
                       samples: samples(scene, quality, pixels: width * height),
                       seed: SIMD4(r(), r(), r(), r()),
                       seed2: SIMD4(twists[Int(r() * 3.99)], r(), r(), r()),
                       skyTop: gray(0.35), skyMid: gray(0.045), skyBottom: gray(0.01),
                       metal: rgb(0.92, 0.92, 0.94), base: rgb(0.22, 0.22, 0.23, 0.05),
                       glass: rgb(0.18, 0.16, 0.14, 1.5), misc: SIMD4(1.0, 0.35, distance, 0.003),
                       rot0: SIMD4(rows.0, 0), rot1: SIMD4(rows.1, 0), rot2: SIMD4(rows.2, 0),
                       offset: SIMD4(offset, 0), sun: SIMD4(0, 0, 1, 0))

        let spin = r() * 6.283
        let sun = normalize(SIMD3<Float>(-0.6, 0.55, 0.45))
        p.sun = SIMD4(cos(spin) * sun.x - sin(spin) * sun.y, sin(spin) * sun.x + cos(spin) * sun.y, sun.z, 0)

        switch tone {
        case .silver:
            break
        case .obsidian:
            p.skyTop = gray(0.02); p.skyMid = gray(0.004); p.skyBottom = gray(0)
            p.metal = rgb(0.78, 0.78, 0.8); p.base = rgb(0.012, 0.012, 0.013, 0.05)
            p.glass = rgb(2.0, 2.0, 1.9, 1.5); p.misc.x = 1.15; p.misc.y = 0.45; p.misc.w = 0.004
        case .pearl:
            p.skyTop = gray(1.0); p.skyMid = gray(0.78); p.skyBottom = gray(0.55)
            p.metal = rgb(0.95, 0.95, 0.96); p.base = rgb(0.86, 0.86, 0.87, 0.2)
            p.glass = rgb(0.3, 0.28, 0.26, 1.5); p.misc.x = 1.05; p.misc.y = 0.18; p.misc.w = 0.002
        case .midnight:
            p.skyTop = rgb(0.05, 0.08, 0.2); p.skyMid = rgb(0.008, 0.012, 0.035); p.skyBottom = rgb(0.002, 0.003, 0.01)
            p.metal = rgb(0.82, 0.86, 0.95); p.base = rgb(0.01, 0.015, 0.04, 0.05)
            p.glass = rgb(1.2, 0.7, 0.25, 1.5); p.misc.x = 1.05; p.misc.y = 0.4
        case .prism:
            p.skyTop = gray(0.45); p.skyMid = gray(0.06); p.skyBottom = gray(0.015)
            p.metal = rgb(0.94, 0.94, 0.95, 0.85); p.base = rgb(0.14, 0.14, 0.15, 0.05)
            p.glass = rgb(0.1, 0.09, 0.08, 1.5)
        case .moss, .custom:
            applyColors(&p, tone.colors ?? CustomTone.standard)
        }
        return p
    }

    private static func linear(_ c: SIMD3<Float>) -> SIMD3<Float> { SIMD3(pow(c.x, 2.2), pow(c.y, 2.2), pow(c.z, 2.2)) }

    /// An accent colour scaled so its brightest channel is 1: the hue to tint metal and lights with.
    private static func hue(_ c: SIMD3<Float>) -> SIMD3<Float> { c / max(0.05, max(c.x, max(c.y, c.z))) }

    /// Backdrop from the background colour, chrome tinted by the accent.
    private static func applyColors(_ p: inout Params, _ colors: CustomTone.Colors) {
        let back = linear(colors.background)
        let tint = SIMD3<Float>(repeating: 0.65) + hue(colors.accent) * 0.35
        if colors.isDark {
            let lift = linear(colors.background * 0.7 + colors.accent * 0.3)
            p.skyTop = SIMD4(lift * 0.6 + back * 0.4, 0); p.skyMid = SIMD4(back, 0); p.skyBottom = SIMD4(back * 0.2, 0)
            p.metal = SIMD4(tint * 0.82, 0); p.base = SIMD4(back * 0.5, 0.05)
            p.glass = SIMD4(hue(colors.accent) * 1.8, 1.5); p.misc.x = 1.12; p.misc.y = 0.42; p.misc.w = 0.004
        } else {
            p.skyTop = SIMD4(back, 0); p.skyMid = SIMD4(back * 0.8, 0); p.skyBottom = SIMD4(back * 0.58, 0)
            p.metal = SIMD4(tint * 0.95, 0); p.base = SIMD4(back * 0.88, 0.2)
            p.glass = SIMD4(linear(colors.accent) * 0.6, 1.5); p.misc.x = 1.05; p.misc.y = 0.18; p.misc.w = 0.002
        }
    }

    private static func rotation(_ a: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let (cx, sx, cy, sy, cz, sz) = (cos(a.x), sin(a.x), cos(a.y), sin(a.y), cos(a.z), sin(a.z))
        // R = Rz * Ry * Rx, written as rows.
        let r0 = SIMD3<Float>(cz * cy, cz * sy * sx - sz * cx, cz * sy * cx + sz * sx)
        let r1 = SIMD3<Float>(sz * cy, sz * sy * sx + cz * cx, sz * sy * cx - cz * sx)
        let r2 = SIMD3<Float>(-sy, cy * sx, cy * cx)
        return (r0, r1, r2)
    }

    private static func makeLights(tone: StudioTone, seed: Int) -> [Light] {
        var rng = ArtRandom(seed &* 17 &+ 5)
        func r() -> Float { Float(rng.next()) }
        let spin = r() * 6.283
        let tilt = (r() - 0.5) * 0.5

        // (direction, half size, softness, rotates with the rig)
        let rig: [(SIMD3<Float>, SIMD2<Float>, Float, Bool)] = [
            (SIMD3(-0.45, 0.55, 0.7), SIMD2(0.45, 0.7), 0.06, true),     // key softbox
            (SIMD3(0.78, 0.12, 0.6), SIMD2(0.05, 1.3), 0.025, true),     // strip
            (SIMD3(-0.75, -0.35, 0.55), SIMD2(0.07, 1.1), 0.03, true),   // second strip
            (SIMD3(0.05, 0.97, -0.2), SIMD2(0.9, 0.5), 0.25, false),     // top light
            (SIMD3(0, 0.15, -1), SIMD2(0.7, 0.45), 0.7, false),          // glow on the backdrop
        ]
        let colors: [SIMD3<Float>]
        switch tone {
        case .silver: colors = [SIMD3(repeating: 2.6), SIMD3(repeating: 4.0), SIMD3(repeating: 1.8), SIMD3(repeating: 2.2), SIMD3(repeating: 0.12)]
        case .obsidian: colors = [SIMD3(repeating: 1.3), SIMD3(repeating: 3.0), SIMD3(repeating: 0.9), SIMD3(repeating: 1.1), SIMD3(repeating: 0.04)]
        case .pearl: colors = [SIMD3(repeating: 1.2), SIMD3(repeating: 1.4), SIMD3(repeating: -0.55), SIMD3(repeating: 0.8), SIMD3(repeating: 0.22)]
        case .midnight: colors = [SIMD3(0.75, 0.85, 1.0) * 2.2, SIMD3(0.8, 0.88, 1.0) * 3.5, SIMD3(0.15, 0.35, 1.0) * 3.0,
                                  SIMD3(0.7, 0.8, 1.0) * 1.8, SIMD3(0.05, 0.1, 0.3) * 0.5]
        case .prism: colors = [SIMD3(1.0, 0.93, 0.86) * 2.6, SIMD3(0.82, 0.9, 1.0) * 4.0, SIMD3(1.0, 0.85, 0.95) * 1.8,
                               SIMD3(repeating: 2.2), SIMD3(repeating: 0.14)]
        case .moss, .custom:
            let palette = tone.colors ?? CustomTone.standard
            let tint = SIMD3<Float>(repeating: 0.6) + hue(palette.accent) * 0.4
            let base: [Float] = palette.isDark ? [1.3, 3.0, 0.9, 1.1, 0.05] : [1.2, 1.4, -0.55, 0.8, 0.22]
            colors = base.enumerated().map { index, value in index == 1 ? SIMD3(repeating: value) : tint * value }
        }

        return rig.enumerated().map { index, light in
            var d = normalize(light.0)
            if light.3 {
                d = SIMD3(cos(spin) * d.x - sin(spin) * d.y, sin(spin) * d.x + cos(spin) * d.y, d.z)
                d = normalize(SIMD3(d.x, d.y + tilt * d.z, d.z))
            }
            let up: SIMD3<Float> = abs(d.y) > 0.95 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0)
            var t1 = normalize(cross(up, d))
            var t2 = cross(d, t1)
            let turn = (r() - 0.5) * 0.9
            (t1, t2) = (cos(turn) * t1 + sin(turn) * t2, -sin(turn) * t1 + cos(turn) * t2)
            return Light(dir: SIMD4(d, 0), t1: SIMD4(t1, 0), t2: SIMD4(t2, 0), color: SIMD4(colors[index], 0),
                         size: SIMD4(light.1.x, light.1.y, light.2, 0))
        }
    }

    private static func makeBlobs(seed: Int) -> [SIMD4<Float>] {
        var rng = ArtRandom(seed &* 13 &+ 3)
        func r() -> Float { Float(rng.next()) }
        // Beads along a wavy path, melted together into one flowing form.
        let (phase, phase2, bend) = (r() * 6.283, r() * 6.283, 1.0 + r() * 1.2)
        return (0..<8).map { i in
            let x = -2.0 + Float(i) * 0.57 + (r() - 0.5) * 0.2
            return SIMD4(x, 0.65 * sin(bend * x + phase), 0.6 * cos(1.3 * x + phase2), 0.28 + 0.3 * r())
        }
    }
}

/// A tiny seeded random number generator, so a wallpaper with the same seed always looks the same.
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

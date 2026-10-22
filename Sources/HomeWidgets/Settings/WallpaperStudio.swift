import SwiftUI
import AppKit

/// Every wallpaper the studio can make: ray-traced studio scenes, ink sketches and pixel art.
enum WallpaperStyle: Hashable, Identifiable {
    case studio(StudioScene)
    case sketch(SketchScene)

    enum Group: String, CaseIterable, Identifiable {
        case studio = "Studio", sketch = "Sketch", poster = "Poster", glitch = "Glitch", pixel = "Pixel"
        var id: String { rawValue }
    }

    static let all: [WallpaperStyle] = StudioScene.allCases.map { .studio($0) } + SketchScene.allCases.map { .sketch($0) }

    init?(rawValue: String) {
        if let scene = StudioScene(rawValue: rawValue) {
            self = .studio(scene)
        } else if let scene = SketchScene(rawValue: rawValue) {
            self = .sketch(scene)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .studio(let scene): return scene.rawValue
        case .sketch(let scene): return scene.rawValue
        }
    }
    var id: String { rawValue }
    var label: String {
        switch self {
        case .studio(let scene): return scene.label
        case .sketch(let scene): return scene.label
        }
    }
    var summary: String {
        switch self {
        case .studio(let scene): return scene.summary
        case .sketch(let scene): return scene.summary
        }
    }
    var group: Group {
        switch self {
        case .studio: return .studio
        case .sketch(let scene):
            switch scene.group {
            case .sketch: return .sketch
            case .poster: return .poster
            case .glitch: return .glitch
            case .pixel: return .pixel
            }
        }
    }

    func render(tone: StudioTone, seed: Int, width: Int, height: Int, quality: StudioRenderer.Quality = .final,
                progress: ((Double) -> Void)? = nil) -> CGImage? {
        switch self {
        case .studio(let scene):
            return StudioRenderer.render(scene, tone: tone, seed: seed, width: width, height: height, quality: quality, progress: progress)
        case .sketch(let scene):
            return SketchRenderer.render(scene, tone: tone, seed: seed, width: width, height: height, progress: progress)
        }
    }
}

/// Desktop wallpapers: ray traced on the GPU (liquid chrome, glass, satin, soft clay) or drawn
/// stroke by stroke (ink sketches, pixel art), rendered at 4K or better and set with one click.
struct WallpaperStudioView: View {
    @AppStorage("studioScene") private var sceneRaw = StudioScene.glassRibbon.rawValue
    @AppStorage("studioTone") private var toneRaw = StudioTone.obsidian.rawValue
    /// Each style keeps its own shuffle, so shuffling one never re-renders the others.
    @AppStorage("wallpaperSeeds") private var seedsRaw = ""
    /// Your Colors: background, ink and accent as RRGGBB.
    @AppStorage("wallpaperCustomColors") private var customRaw = ""
    @AppStorage("wallpaperResolution") private var resolutionRaw = OutputSize.best.rawValue
    @State private var preview: NSImage?
    @State private var previewing = false
    @State private var progress: Double?
    @State private var status: String?

    private var style: WallpaperStyle { WallpaperStyle(rawValue: sceneRaw) ?? .studio(.glassRibbon) }
    private var tone: StudioTone { StudioTone(rawValue: toneRaw) ?? .obsidian }
    private var resolution: OutputSize { OutputSize(rawValue: resolutionRaw) ?? .best }

    private var seeds: [String: Int] {
        var out: [String: Int] = [:]
        for pair in seedsRaw.split(separator: ";") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let value = Int(parts[1]) { out[String(parts[0])] = value }
        }
        return out
    }
    private func seed(for style: WallpaperStyle) -> Int { seeds[style.rawValue] ?? 2026 }
    private var seed: Int { seed(for: style) }

    private var customColors: CustomTone.Colors {
        let parts = customRaw.split(separator: ",").compactMap { UInt32($0, radix: 16) }
        guard parts.count == 3 else { return CustomTone.standard }
        return CustomTone.Colors(background: CustomTone.color(hex: parts[0]), ink: CustomTone.color(hex: parts[1]), accent: CustomTone.color(hex: parts[2]))
    }
    /// What a render depends on besides style and seed: the tone, and for Your Colors the colours too.
    private var toneKey: String { tone == .custom ? "custom-\(customRaw)" : tone.rawValue }

    private var aspect: CGFloat {
        let size = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 10)
        return size.width / max(1, size.height)
    }

    enum OutputSize: String, CaseIterable, Identifiable {
        case best, uhd4k, uhd5k, uhd6k, uhd8k
        var id: String { rawValue }
        var label: String {
            switch self {
            case .best: return "Best for each display (4K or sharper)"
            case .uhd4k: return "4K"
            case .uhd5k: return "5K"
            case .uhd6k: return "6K"
            case .uhd8k: return "8K"
            }
        }
        /// Pixel size for a display: at least 4K wide, never below the display's own pixels.
        func pixels(for screen: NSScreen?) -> (Int, Int) {
            let frame = screen?.frame.size ?? CGSize(width: 1728, height: 1117)
            let ratio = frame.height / max(1, frame.width)
            let native = frame.width * (screen?.backingScaleFactor ?? 2)
            let width: CGFloat
            switch self {
            case .best: width = max(3840, native)
            case .uhd4k: width = 3840
            case .uhd5k: width = 5120
            case .uhd6k: width = 6016
            case .uhd8k: width = 7680
            }
            return (Int(width), Int((width * ratio).rounded()))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wallpapers").font(.largeTitle.bold())
                    Text("Ray-traced studio renders, ink sketches, posters, glitch art and pixel art. Pick a style and a tone (or make your own colors), shuffle the one you're on until it's perfect, then set it in 4K or sharper.")
                        .foregroundStyle(.secondary)
                }

                ZStack {
                    if let preview {
                        Image(nsImage: preview).resizable().aspectRatio(aspect, contentMode: .fit)
                    } else {
                        Rectangle().fill(Color.black).aspectRatio(aspect, contentMode: .fit)
                    }
                    if previewing { ProgressView().controlSize(.large) }
                }
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
                .onTapGesture { shuffle() }
                .help("Click to shuffle")

                HStack(spacing: 10) {
                    Button { shuffle() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .keyboardShortcut("r", modifiers: .command)
                    Picker("Size", selection: $resolutionRaw) {
                        ForEach(OutputSize.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .fixedSize()
                    Spacer()
                    if let progress {
                        ProgressView(value: progress).frame(width: 120)
                    } else if let status {
                        Text(status).font(.callout).foregroundStyle(.secondary)
                    }
                    Button { save() } label: { Label("Save PNG…", systemImage: "square.and.arrow.down") }
                        .disabled(progress != nil)
                    Button { setWallpaper() } label: { Label("Set as Wallpaper", systemImage: "photo.on.rectangle") }
                        .buttonStyle(.borderedProminent)
                        .disabled(progress != nil)
                }

                ForEach(WallpaperStyle.Group.allCases) { group in
                    Text(group.rawValue).font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 12) {
                        ForEach(WallpaperStyle.all.filter { $0.group == group }) { item in
                            Button { sceneRaw = item.rawValue } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    SceneThumbnail(style: item, tone: tone, toneKey: toneKey, custom: customColors,
                                                   seed: seed(for: item), aspect: aspect)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(item == style ? Color.accentColor : Color.clear, lineWidth: 2.5))
                                    Text(item.label).font(.caption.weight(item == style ? .semibold : .regular))
                                    Text(item.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                        .frame(height: 26, alignment: .topLeading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("Tone").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(StudioTone.allCases) { item in
                        Button { toneRaw = item.rawValue } label: {
                            VStack(spacing: 5) {
                                LinearGradient(colors: [Color(hex: item.swatch.0), Color(hex: item.swatch.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(item == tone ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: item == tone ? 2.5 : 1))
                                Text(item.label).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                if tone == .custom {
                    HStack(spacing: 18) {
                        colorWell("Background", 0)
                        colorWell("Ink", 1)
                        colorWell("Accent", 2)
                        Spacer()
                        Button("Start from Moss") { customRaw = Self.encode(CustomTone.moss) }
                    }
                    Text("Background fills the paper or studio backdrop, Ink draws lines and chrome, Accent tints glitches, gradients and seals.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Text("Studio styles are ray traced on your Mac's graphics chip; sketches and pixel art are drawn stroke by stroke, so they stay crisp at any size. Tone sets the paper and ink too. Saved in Pictures › Home Widgets Wallpapers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .task(id: "\(sceneRaw)|\(toneKey)|\(seed)") { await renderPreview() }
        .onAppear { CustomTone.colors = customColors }
    }

    private static func encode(_ colors: CustomTone.Colors) -> String {
        [colors.background, colors.ink, colors.accent].map { String(format: "%06X", CustomTone.hex($0)) }.joined(separator: ",")
    }

    private func colorWell(_ title: String, _ index: Int) -> some View {
        let binding = Binding<Color>(
            get: {
                let colors = customColors
                let value = [colors.background, colors.ink, colors.accent][index]
                return Color(hex: CustomTone.hex(value))
            },
            set: { color in
                var parts = Self.encode(customColors).split(separator: ",").map(String.init)
                parts[index] = color.hexString
                customRaw = parts.joined(separator: ",")
                CustomTone.colors = customColors
            })
        return ColorPicker(title, selection: binding, supportsOpacity: false)
    }

    /// New randomness for the selected style only.
    private func shuffle() {
        var updated = seeds
        updated[style.rawValue] = Int.random(in: 1...999_999)
        seedsRaw = updated.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ";")
        status = nil
    }

    private func renderPreview() async {
        previewing = true
        CustomTone.colors = customColors
        let (sc, t, s, a) = (style, tone, seed, aspect)
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let width = 1600
            return sc.render(tone: t, seed: s, width: width, height: Int(CGFloat(width) / a), quality: .preview)
        }.value
        guard !Task.isCancelled else { return }
        if let image { preview = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)) }
        previewing = false
    }

    private static var folder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let folder = pictures.appendingPathComponent("Home Widgets Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Renders off the main thread and writes a PNG.
    private func renderFile(width: Int, height: Int, to url: URL, share: Double, base: Double) async -> Bool {
        CustomTone.colors = customColors
        let (sc, t, s) = (style, tone, seed)
        return await Task.detached(priority: .userInitiated) { () -> Bool in
            let image = sc.render(tone: t, seed: s, width: width, height: height) { value in
                DispatchQueue.main.async { if self.progress != nil { self.progress = base + value * share } }
            }
            guard let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
            return (try? data.write(to: url)) != nil
        }.value
    }

    private func fileName(_ width: Int, _ height: Int, suffix: String = "") -> String {
        "\(style.label) \(tone.label) \(seed) \(width)x\(height)\(suffix).png"
    }

    private func setWallpaper() {
        progress = 0
        status = nil
        let screens = NSScreen.screens
        Task {
            var done = 0
            for (index, screen) in screens.enumerated() {
                let (w, h) = resolution.pixels(for: screen)
                // A new file name each time, or macOS keeps showing the cached old picture.
                let url = Self.folder.appendingPathComponent(fileName(w, h, suffix: screens.count > 1 ? " (\(index + 1))" : ""))
                let ok = await renderFile(width: w, height: h, to: url, share: 1 / Double(screens.count), base: Double(index) / Double(screens.count))
                if ok, (try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])) != nil { done += 1 }
            }
            progress = nil
            status = done == 0 ? "Couldn't set the wallpaper" : done == 1 ? "Wallpaper set ✓" : "Set on \(done) displays ✓"
        }
    }

    private func save() {
        let (w, h) = resolution.pixels(for: NSScreen.main)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = fileName(w, h)
        panel.directoryURL = Self.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        progress = 0
        Task {
            let ok = await renderFile(width: w, height: h, to: url, share: 1, base: 0)
            progress = nil
            status = ok ? "Saved \(w)×\(h) ✓" : "Couldn't save"
        }
    }
}

/// A small render of each style in the current tone and seed (cached).
private struct SceneThumbnail: View {
    let style: WallpaperStyle
    let tone: StudioTone
    let toneKey: String
    let custom: CustomTone.Colors
    let seed: Int
    let aspect: CGFloat
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Color.black.opacity(0.85)
                ProgressView().controlSize(.small)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .task(id: "\(style.rawValue)|\(toneKey)|\(seed)") {
            let key = "\(style.rawValue)|\(toneKey)|\(seed)" as NSString
            if let cached = Self.cache.object(forKey: key) { image = cached; return }
            CustomTone.colors = custom
            let (sc, t, s, a) = (style, tone, seed, aspect)
            let rendered = await Task.detached(priority: .utility) { () -> CGImage? in
                sc.render(tone: t, seed: s, width: 400, height: Int(400 / a), quality: .thumbnail)
            }.value
            guard let rendered else { return }
            let ns = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
            Self.cache.setObject(ns, forKey: key)
            image = ns
        }
    }
}

import SwiftUI
import AppKit

/// Desktop wallpapers ray traced on the GPU — liquid chrome, glass, satin and soft clay under
/// studio lights — rendered at 4K or better and set with one click.
struct WallpaperStudioView: View {
    @AppStorage("studioScene") private var sceneRaw = StudioScene.glassRibbon.rawValue
    @AppStorage("studioTone") private var toneRaw = StudioTone.obsidian.rawValue
    @AppStorage("wallpaperSeed") private var seed = 2026
    @AppStorage("wallpaperResolution") private var resolutionRaw = OutputSize.best.rawValue
    @State private var preview: NSImage?
    @State private var previewing = false
    @State private var progress: Double?
    @State private var status: String?

    private var scene: StudioScene { StudioScene(rawValue: sceneRaw) ?? .glassRibbon }
    private var tone: StudioTone { StudioTone(rawValue: toneRaw) ?? .obsidian }
    private var resolution: OutputSize { OutputSize(rawValue: resolutionRaw) ?? .best }

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
                    Text("Ray-traced studio renders: liquid chrome, real glass and satin under soft lights. Pick a style and tone, shuffle until it's perfect, then set it in 4K or sharper.")
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

                Text("Style").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 12) {
                    ForEach(StudioScene.allCases) { item in
                        Button { sceneRaw = item.rawValue } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                SceneThumbnail(scene: item, tone: tone, seed: seed, aspect: aspect)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(item == scene ? Color.accentColor : Color.clear, lineWidth: 2.5))
                                Text(item.label).font(.caption.weight(item == scene ? .semibold : .regular))
                                Text(item.summary).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                    .frame(height: 26, alignment: .topLeading)
                            }
                        }
                        .buttonStyle(.plain)
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

                Text("Rendered on your Mac's graphics chip with reflections, refraction and soft studio lighting. Saved in Pictures › Home Widgets Wallpapers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .task(id: "\(sceneRaw)|\(toneRaw)|\(seed)") { await renderPreview() }
    }

    private func shuffle() {
        seed = Int.random(in: 1...999_999)
        status = nil
    }

    private func renderPreview() async {
        previewing = true
        let (sc, t, s, a) = (scene, tone, seed, aspect)
        let image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let width = 1600
            return StudioRenderer.render(sc, tone: t, seed: s, width: width, height: Int(CGFloat(width) / a), quality: .preview)
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
        let (sc, t, s) = (scene, tone, seed)
        return await Task.detached(priority: .userInitiated) { () -> Bool in
            let image = StudioRenderer.render(sc, tone: t, seed: s, width: width, height: height) { value in
                DispatchQueue.main.async { if self.progress != nil { self.progress = base + value * share } }
            }
            guard let image, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
            return (try? data.write(to: url)) != nil
        }.value
    }

    private func fileName(_ width: Int, _ height: Int, suffix: String = "") -> String {
        "\(scene.label) \(tone.label) \(seed) \(width)x\(height)\(suffix).png"
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
    let scene: StudioScene
    let tone: StudioTone
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
        .task(id: "\(scene.rawValue)|\(tone.rawValue)|\(seed)") {
            let key = "\(scene.rawValue)|\(tone.rawValue)|\(seed)" as NSString
            if let cached = Self.cache.object(forKey: key) { image = cached; return }
            let (sc, t, s, a) = (scene, tone, seed, aspect)
            let rendered = await Task.detached(priority: .utility) { () -> CGImage? in
                StudioRenderer.render(sc, tone: t, seed: s, width: 400, height: Int(400 / a), quality: .thumbnail)
            }.value
            guard let rendered else { return }
            let ns = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
            Self.cache.setObject(ns, forKey: key)
            image = ns
        }
    }
}

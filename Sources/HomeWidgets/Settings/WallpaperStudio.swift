import SwiftUI
import AppKit

/// Makes abstract desktop wallpapers from maths — the same engine as the art widgets —
/// rendered at your display's full resolution and set with one click.
struct WallpaperStudioView: View {
    @AppStorage("wallpaperStyle") private var styleRaw = ArtStyle.ribbons.rawValue
    @AppStorage("wallpaperPalette") private var paletteID = "sonoma"
    @AppStorage("wallpaperSeed") private var seed = 2026
    @State private var working = false
    @State private var status: String?

    private var style: ArtStyle { ArtStyle(rawValue: styleRaw) ?? .ribbons }
    private var palette: ArtPalette { ArtPalette.named(paletteID) }

    private var aspect: CGFloat {
        let size = NSScreen.main?.frame.size ?? CGSize(width: 16, height: 10)
        return size.width / max(1, size.height)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wallpapers").font(.largeTitle.bold())
                    Text("Abstract wallpapers drawn from maths, like Apple's. Pick a style and colours, shuffle until you love it, then set it.")
                        .foregroundStyle(.secondary)
                }

                AbstractArt(style: style, palette: palette, seed: seed)
                    .aspectRatio(aspect, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                    .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                    .onTapGesture { shuffle() }
                    .help("Click to shuffle")

                HStack(spacing: 10) {
                    Button { shuffle() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .keyboardShortcut("r", modifiers: .command)
                    Spacer()
                    if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
                    if working { ProgressView().controlSize(.small) }
                    Button { save() } label: { Label("Save PNG…", systemImage: "square.and.arrow.down") }
                        .disabled(working)
                    Button { setWallpaper() } label: { Label("Set as Wallpaper", systemImage: "photo.on.rectangle") }
                        .buttonStyle(.borderedProminent)
                        .disabled(working)
                }

                Text("Style").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                    ForEach(ArtStyle.allCases) { item in
                        Button { styleRaw = item.rawValue } label: {
                            VStack(spacing: 5) {
                                AbstractArt(style: item, palette: palette, seed: seed)
                                    .aspectRatio(aspect, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(item == style ? Color.accentColor : Color.clear, lineWidth: 2.5))
                                Text(item.label).font(.caption.weight(item == style ? .semibold : .regular))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Colours").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(ArtPalette.all) { item in
                        Button { paletteID = item.id } label: {
                            VStack(spacing: 5) {
                                HStack(spacing: 0) {
                                    ForEach(item.colors.indices, id: \.self) { Color(hex: item.colors[$0]) }
                                }
                                .frame(height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(item.id == paletteID ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: item.id == paletteID ? 2.5 : 1))
                                Text(item.name).font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Wallpapers are saved in Pictures › Home Widgets Wallpapers. Each display gets one at its own resolution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func shuffle() {
        seed = Int.random(in: 1...999_999)
        status = nil
    }

    private static var folder: URL {
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let folder = pictures.appendingPathComponent("Home Widgets Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Draws the wallpaper at a screen's real pixel size.
    @MainActor
    private func render(size: CGSize, scale: CGFloat) -> Data? {
        let renderer = ImageRenderer(content: AbstractArt(style: style, palette: palette, seed: seed).frame(width: size.width, height: size.height))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func setWallpaper() {
        working = true
        status = "Drawing…"
        // Let the progress indicator appear before the (main-thread) render starts.
        DispatchQueue.main.async {
            var done = 0
            for (index, screen) in NSScreen.screens.enumerated() {
                guard let data = render(size: screen.frame.size, scale: screen.backingScaleFactor) else { continue }
                // A new file name each time, or macOS keeps showing the cached old picture.
                let url = Self.folder.appendingPathComponent("\(style.label) \(palette.name) \(seed)-\(index + 1).png")
                do {
                    try data.write(to: url)
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    done += 1
                } catch {
                    status = "Couldn't set the wallpaper: \(error.localizedDescription)"
                }
            }
            working = false
            if done > 0 { status = done == 1 ? "Wallpaper set ✓" : "Set on \(done) displays ✓" }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(style.label) \(palette.name) \(seed).png"
        panel.directoryURL = Self.folder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let screen = NSScreen.main
        working = true
        DispatchQueue.main.async {
            if let data = render(size: screen?.frame.size ?? CGSize(width: 2560, height: 1600), scale: screen?.backingScaleFactor ?? 2) {
                try? data.write(to: url)
                status = "Saved ✓"
            }
            working = false
        }
    }
}

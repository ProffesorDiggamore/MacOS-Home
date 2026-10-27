#if DEBUG
import SwiftUI
import AppKit

/// Debug builds only: `HomeWidgets -HWSnapshots <folder>` renders every widget at every size it
/// supports (gallery sample data) into contact sheets, then quits. Nothing is shown on the desktop
/// and saved widgets are never loaded. Used to check layouts fill their space.
@MainActor
enum Snapshots {
    static func run(to folder: String, kindsPerSheet: Int = 3, scale: CGFloat = 0.6) {
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let filter = UserDefaults.standard.string(forKey: "HWSnapshotKinds")?.components(separatedBy: ",")
        let kinds = WidgetKind.allCases.filter { filter == nil || filter!.contains($0.rawValue) }
        var sheet = 0
        for start in stride(from: 0, to: kinds.count, by: kindsPerSheet) {
            let group = Array(kinds[start..<min(kinds.count, start + kindsPerSheet)])
            let rows = group.map { kind in (kind, kind.sizes.compactMap { render(kind, $0) }) }
            if let image = compose(rows, scale: scale) {
                sheet += 1
                let name = String(format: "%02d-", sheet) + group.map(\.rawValue).joined(separator: "-") + ".png"
                try? image.write(to: out.appendingPathComponent(name))
            }
        }
        exit(0)
    }

    /// `HomeWidgets -HWWallpapers <folder>` renders every wallpaper style (or those in
    /// `-HWWallpaperStyles a,b`) in every tone (or `-HWWallpaperTones`) at `-HWWallpaperWidth`
    /// (default 1600), with `-HWWallpaperSeed`, then quits. Prints how long each one took.
    static func wallpapers(to folder: String) {
        NSApp.setActivationPolicy(.prohibited)
        let defaults = UserDefaults.standard
        let out = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let styles = defaults.string(forKey: "HWWallpaperStyles")?.components(separatedBy: ",").compactMap(WallpaperStyle.init(rawValue:))
            ?? WallpaperStyle.all
        let tones = defaults.string(forKey: "HWWallpaperTones")?.components(separatedBy: ",").compactMap(StudioTone.init(rawValue:))
            ?? StudioTone.allCases
        let width = defaults.integer(forKey: "HWWallpaperWidth") > 0 ? defaults.integer(forKey: "HWWallpaperWidth") : 1600
        let height = width * 1964 / 3024
        let seed = defaults.integer(forKey: "HWWallpaperSeed") != 0 ? defaults.integer(forKey: "HWWallpaperSeed") : 2026
        for style in styles {
            for tone in tones {
                let start = Date()
                guard let image = style.render(tone: tone, seed: seed, width: width, height: height, quality: .preview),
                      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    print("✗ \(style.rawValue) \(tone.rawValue)")
                    continue
                }
                try? data.write(to: out.appendingPathComponent("\(style.rawValue)-\(tone.rawValue)-\(seed).png"))
                print(String(format: "✓ %@ %@ %.2fs", style.rawValue, tone.rawValue, Date().timeIntervalSince(start)))
            }
        }
        exit(0)
    }

    private static func render(_ kind: WidgetKind, _ size: WidgetSize) -> (WidgetSize, CGImage)? {
        let model = PreviewModels.shared.model(for: kind, size: size)
        model.styleOverride = .solid // glass materials can't be drawn off screen
        let dims = size.dimensions
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        let view = WidgetView(model: model)
            .environment(\.widgetContext, .gallery)
            .frame(width: dims.width, height: dims.height)
            .background(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.cgImage.map { (size, $0) }
    }

    private static func compose(_ rows: [(WidgetKind, [(WidgetSize, CGImage)])], scale: CGFloat) -> Data? {
        let gap: CGFloat = 16, label: CGFloat = 22
        let heights = rows.map { row in row.1.map { $0.0.dimensions.height }.max() ?? 0 }
        let widths = rows.map { row in row.1.reduce(0) { $0 + $1.0.dimensions.width + gap } }
        let width = (widths.max() ?? 0) + gap
        let height = heights.reduce(0) { $0 + $1 + label + gap } + gap
        let pixels = NSSize(width: width * scale, height: height * scale)
        let image = NSImage(size: pixels)
        image.lockFocus()
        NSColor(white: 0.06, alpha: 1).setFill()
        NSRect(origin: .zero, size: pixels).fill()
        var y = height - gap
        for (index, row) in rows.enumerated() {
            y -= label
            let title = "\(row.0.title)  (\(row.0.rawValue))" as NSString
            title.draw(at: NSPoint(x: gap * scale, y: y * scale),
                       withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13 * scale * 1.4), .foregroundColor: NSColor.white])
            y -= heights[index]
            var x = gap
            for (size, cg) in row.1 {
                let dims = size.dimensions
                let rect = NSRect(x: x * scale, y: (y + heights[index] - dims.height) * scale,
                                  width: dims.width * scale, height: dims.height * scale)
                NSImage(cgImage: cg, size: dims).draw(in: rect)
                x += dims.width + gap
            }
            y -= gap
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif

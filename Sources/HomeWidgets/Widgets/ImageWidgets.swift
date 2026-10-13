import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Photo

enum PhotoKeys {
    static let images = ConfigKey<[String]>("images", [])
    static let path = ConfigKey("path", "")
    static let minutes = ConfigKey("minutes", 30)
    static let frame = ConfigKey("frame", PhotoFrame.fill)
    static let caption = ConfigKey("caption", "")
}

enum PhotoFrame: String, ConfigOption {
    case fill, polaroid, rounded

    var label: String {
        switch self {
        case .fill: return "Edge to Edge"
        case .polaroid: return "Polaroid"
        case .rounded: return "Framed"
        }
    }
}

struct PhotoWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @State private var manualOffset = 0
    @State private var dropTargeted = false

    private var sources: [String] {
        let stored = model[PhotoKeys.images].filter { FileManager.default.fileExists(atPath: $0) }
        if !stored.isEmpty { return stored }
        let folder = (model[PhotoKeys.path] as NSString).expandingTildeInPath
        guard !folder.isEmpty else { return [] }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) else { return [] }
        if isDirectory.boolValue {
            return ImageLoader.imageFiles(in: URL(fileURLWithPath: folder)).map(\.path)
        }
        return [folder]
    }

    var body: some View {
        let interval = TimeInterval(max(1, model[PhotoKeys.minutes]) * 60)
        let frame = model[PhotoKeys.frame]
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: interval)) { timeline in
            let list = sources
            let slot = Int(timeline.date.timeIntervalSinceReferenceDate / interval) + manualOffset
            let path = list.isEmpty ? nil : list[((slot % list.count) + list.count) % list.count]
            content(path: path, frame: frame, count: list.count)
        }
        .widgetBackground(background(frame: frame))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            ImageStore.importDrop(providers) { paths in
                guard !paths.isEmpty else { return }
                model.config[PhotoKeys.images] = model[PhotoKeys.images] + paths
            }
        }
    }

    private func background(frame: PhotoFrame) -> CustomBackground? {
        // A cut-out or transparent PNG floats on the wallpaper instead of sitting in a box.
        if frame == .fill, let first = sources.first, sources.count == 1, ImageStore.hasTransparency(first) {
            return .edgeToEdge
        }
        if context == .gallery || !sources.isEmpty {
            switch frame {
            case .fill: return .edgeToEdge
            case .polaroid: return .color(Color(white: 0.97))
            case .rounded: return nil
            }
        }
        return nil
    }

    @ViewBuilder
    private func content(path: String?, frame: PhotoFrame, count: Int) -> some View {
        let size = model.size.dimensions
        if let path, let image = ImageStore.image(at: path, maxPixel: Int(max(size.width, size.height) * 2.2)) {
            photo(image, frame: frame, size: size, count: count)
        } else if context == .gallery {
            photo(nil, frame: frame, size: size, count: 1)
        } else {
            WidgetMessage(symbol: "photo.on.rectangle.angled", title: "Drop photos here",
                          detail: "Or right-click › Edit Widget to choose photos or a folder.")
        }
    }

    /// A pretty placeholder for the gallery.
    private var samplePhoto: some View {
        LinearGradient(colors: [Color(hex: 0xFF9A8B), Color(hex: 0xFF6A88), Color(hex: 0x6A82FB)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "mountain.2.fill").font(.system(size: 54)).foregroundStyle(Color.white.opacity(0.85)))
    }

    @ViewBuilder
    private func picture(_ image: NSImage?) -> some View {
        if let image {
            let floating = sources.count == 1 && sources.first.map(ImageStore.hasTransparency) == true
            Image(nsImage: image).resizable().aspectRatio(contentMode: floating ? .fit : .fill)
        } else {
            samplePhoto
        }
    }

    @ViewBuilder
    private func photo(_ image: NSImage?, frame: PhotoFrame, size: CGSize, count: Int) -> some View {
        switch frame {
        case .fill:
            picture(image)
                .frame(width: size.width, height: size.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { if count > 1 { manualOffset += 1 } }
        case .polaroid:
            let caption = model[PhotoKeys.caption]
            VStack(spacing: 6) {
                picture(image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(Rectangle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
                Text(caption.isEmpty ? " " : caption)
                    .font(.custom("Marker Felt", size: model.family == .small ? 13 : 16))
                    .foregroundStyle(Color(white: 0.2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .environment(\.colorScheme, .light)
            .contentShape(Rectangle())
            .onTapGesture { if count > 1 { manualOffset += 1 } }
        case .rounded:
            picture(image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(9)
                .contentShape(Rectangle())
                .onTapGesture { if count > 1 { manualOffset += 1 } }
        }
    }
}

// MARK: - Sticker

enum StickerKeys {
    static let image = ConfigKey("image", "")
    static let fill = ConfigKey("fill", false)
    static let rounded = ConfigKey("rounded", false)
    /// Cut the subject out of photos that have a background.
    static let autoCutout = ConfigKey("autoCutout", true)
    /// The image as you added it, kept so you can undo the cut-out.
    static let original = ConfigKey("original", "")
    /// The last image we already looked at, so we never cut out twice.
    static let checked = ConfigKey("checked", "")
}

/// Turns a sticker's photo into a cut-out once, in the background.
@MainActor
enum StickerCutout {
    static var working = Set<UUID>()

    static func run(_ model: WidgetModel, force: Bool = false) {
        let path = model[StickerKeys.image]
        guard !path.isEmpty, !working.contains(model.id) else { return }
        guard force || (model[StickerKeys.autoCutout] && model[StickerKeys.checked] != path) else { return }
        if !force && ImageStore.hasTransparency(path) {
            model.config[StickerKeys.checked] = path // already a cut-out: leave it alone
            return
        }
        working.insert(model.id)
        model.objectWillChange.send()
        Task { @MainActor in
            let cut = await ImageStore.cutOutSubject(path)
            working.remove(model.id)
            guard model[StickerKeys.image] == path else { return } // replaced meanwhile
            if let cut {
                let original = model[StickerKeys.original]
                if original.isEmpty || original != path { model.config[StickerKeys.original] = path }
                model.config[StickerKeys.image] = cut
                model.config[StickerKeys.checked] = cut
            } else {
                model.config[StickerKeys.checked] = path
                model.objectWillChange.send()
            }
        }
    }

    static func restoreOriginal(_ model: WidgetModel) {
        let original = model[StickerKeys.original]
        guard !original.isEmpty, FileManager.default.fileExists(atPath: original) else { return }
        let cut = model[StickerKeys.image]
        model.config[StickerKeys.image] = original
        model.config[StickerKeys.checked] = original
        model.config[StickerKeys.original] = ""
        if cut != original { ImageStore.removeIfStored(cut) }
    }
}

/// An image floating on the desktop with no widget box (PNGs with transparency look great).
struct StickerWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetContext) private var context
    @State private var dropTargeted = false

    private var path: String { model[StickerKeys.image] }

    var body: some View {
        let size = model.size.dimensions
        let image = ImageStore.image(at: path, maxPixel: Int(max(size.width, size.height) * 2.2))
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: model[StickerKeys.fill] ? .fill : .fit)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: model[StickerKeys.rounded] ? Layout.cornerRadius : 0, style: .continuous))
            } else if context == .gallery {
                Text("😎")
                    .font(.system(size: model.family == .small ? 96 : 150))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("Drop an image or emoji")
                        .font(.system(size: 12, weight: .semibold))
                    Button("Paste Image") { pasteImage() }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .widgetBackground(image != nil || context == .gallery ? CustomBackground.edgeToEdge : nil)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
            }
            if StickerCutout.working.contains(model.id) {
                Label("Removing background…", systemImage: "wand.and.stars")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
        }
        .task(id: path) {
            if context == .desktop { StickerCutout.run(model) }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $dropTargeted) { providers in
            ImageStore.importDrop(providers) { paths in
                guard let first = paths.first else { return }
                replaceImage(with: first)
            }
        }
    }

    private func pasteImage() {
        if let stored = ImageStore.importFromPasteboard() {
            replaceImage(with: stored)
        } else {
            NSSound.beep()
        }
    }

    private func replaceImage(with newPath: String) {
        let old = model[StickerKeys.image]
        let original = model[StickerKeys.original]
        model.config[StickerKeys.image] = newPath
        model.config[StickerKeys.original] = ""
        if !old.isEmpty && old != newPath { ImageStore.removeIfStored(old) }
        if !original.isEmpty && original != newPath { ImageStore.removeIfStored(original) }
    }
}

// MARK: - Text

enum TextKeys {
    static let text = ConfigKey("text", "Stay humble. Work hard. Be kind.")
    static let font = ConfigKey("font", TextFont.rounded)
    static let size = ConfigKey("size", 26.0)
    static let alignment = ConfigKey("alignment", TextAlign.center)
    static let color = ConfigKey("color", TextColor.primary)
}

enum TextFont: String, ConfigOption {
    case rounded, standard, serif, mono, marker, chalk, typewriter, script

    var label: String {
        switch self {
        case .rounded: return "Rounded"
        case .standard: return "SF Pro"
        case .serif: return "New York"
        case .mono: return "Monospaced"
        case .marker: return "Marker Felt"
        case .chalk: return "Chalkboard"
        case .typewriter: return "American Typewriter"
        case .script: return "Snell Roundhand"
        }
    }

    func font(size: CGFloat) -> Font {
        switch self {
        case .rounded: return .system(size: size, weight: .bold, design: .rounded)
        case .standard: return .system(size: size, weight: .semibold)
        case .serif: return .system(size: size, weight: .medium, design: .serif)
        case .mono: return .system(size: size, weight: .medium, design: .monospaced)
        case .marker: return .custom("Marker Felt", size: size)
        case .chalk: return .custom("Chalkboard SE", size: size)
        case .typewriter: return .custom("American Typewriter", size: size)
        case .script: return .custom("Snell Roundhand", size: size * 1.15)
        }
    }
}

enum TextAlign: String, ConfigOption {
    case leading, center, trailing
    var label: String { rawValue.capitalized }
    var alignment: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    var frameAlignment: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

enum TextColor: String, ConfigOption {
    case primary, accent, red, orange, yellow, green, blue, purple, pink, rainbow

    var label: String { self == .primary ? "Automatic" : rawValue.capitalized }

    func style(accent: Color) -> AnyShapeStyle {
        switch self {
        case .primary: return AnyShapeStyle(HierarchicalShapeStyle.primary)
        case .accent: return AnyShapeStyle(accent)
        case .red: return AnyShapeStyle(Color.red)
        case .orange: return AnyShapeStyle(Color.orange)
        case .yellow: return AnyShapeStyle(Color.yellow)
        case .green: return AnyShapeStyle(Color.green)
        case .blue: return AnyShapeStyle(Color.blue)
        case .purple: return AnyShapeStyle(Color.purple)
        case .pink: return AnyShapeStyle(Color.pink)
        case .rainbow:
            return AnyShapeStyle(LinearGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple],
                                                startPoint: .leading, endPoint: .trailing))
        }
    }
}

struct TextWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetAccent) private var accent

    var body: some View {
        let align = model[TextKeys.alignment]
        Text(model[TextKeys.text])
            .font(model[TextKeys.font].font(size: CGFloat(model[TextKeys.size]) * (model.family == .large ? 1.5 : 1)))
            .foregroundStyle(model[TextKeys.color].style(accent: accent))
            .multilineTextAlignment(align.alignment)
            .minimumScaleFactor(0.3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: align.frameAlignment)
            .widgetPadding(16)
    }
}

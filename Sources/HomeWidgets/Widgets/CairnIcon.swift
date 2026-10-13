import SwiftUI
import AppKit

/// Draws a Cairn page icon. Cairn stores one of three things in a note's `icon:` field:
/// an emoji, a made icon recipe (`ci:1|shape|bg|fg|glyph`), or a tiny `data:image/…` picture.
/// Without this the widget printed the recipe text instead of the icon.
struct CairnIcon: View {
    let value: String
    var size: CGFloat = 16

    var body: some View {
        if value.hasPrefix("data:image/"), let image = Self.dataImage(value) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else if let spec = Spec(value) {
            made(spec)
        } else {
            Text(value).font(.system(size: size * 0.95))
        }
    }

    // MARK: Made icons

    private struct Spec {
        var shape: String
        var bg: [Color]
        var fg: Color
        var glyph: String // i:name, e:😀, t:AB, p:size:palette:cells

        init?(_ value: String) {
            guard value.hasPrefix("ci:1|") else { return nil }
            let parts = value.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 5 else { return nil }
            shape = parts[1]
            bg = parts[2].split(separator: ",").compactMap { CairnIcon.color(String($0)) }
            fg = CairnIcon.color(parts[3]) ?? .white
            glyph = parts[4...].joined(separator: "|")
        }
    }

    @ViewBuilder
    private func made(_ spec: Spec) -> some View {
        let radius: CGFloat = spec.shape == "c" ? size / 2 : spec.shape == "q" ? size * 0.23 : spec.shape == "s" ? size * 0.06 : 0
        let hasBackground = spec.shape != "n" && !spec.bg.isEmpty
        ZStack {
            if hasBackground {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: spec.bg.count == 1 ? [spec.bg[0], spec.bg[0]] : spec.bg,
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            glyph(spec, inner: hasBackground ? size * 0.6 : size * 0.9)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func glyph(_ spec: Spec, inner: CGFloat) -> some View {
        let raw = spec.glyph
        if raw.hasPrefix("i:") {
            Image(systemName: Self.symbols[String(raw.dropFirst(2))] ?? "sparkles")
                .font(.system(size: inner * 0.82, weight: .semibold))
                .foregroundStyle(spec.fg)
        } else if raw.hasPrefix("e:") {
            Text(String(raw.dropFirst(2))).font(.system(size: inner * 0.9))
        } else if raw.hasPrefix("t:") {
            Text(String(raw.dropFirst(2)))
                .font(.system(size: inner * 0.62, weight: .bold, design: .rounded))
                .foregroundStyle(spec.fg)
                .minimumScaleFactor(0.5)
        } else if raw.hasPrefix("p:") {
            PixelGlyph(recipe: String(raw.dropFirst(2)))
                .frame(width: inner * 1.1, height: inner * 1.1)
        }
    }

    // Cairn's symbol names → SF Symbols.
    static let symbols: [String: String] = [
        "sparkles": "sparkles", "star": "star.fill", "heart": "heart.fill", "rocket": "paperplane.fill",
        "lightbulb": "lightbulb.fill", "brain": "brain.head.profile", "book": "book.fill", "graduation": "graduationcap.fill",
        "calculator": "plus.forwardslash.minus", "flask": "flask.fill", "atom": "atom", "code": "chevron.left.forwardslash.chevron.right",
        "bug": "ladybug.fill", "pen": "pencil.tip", "palette": "paintpalette.fill", "camera": "camera.fill", "music": "music.note",
        "gamepad": "gamecontroller.fill", "puzzle": "puzzlepiece.fill", "trophy": "trophy.fill", "award": "rosette", "target": "target",
        "flag": "flag.fill", "flame": "flame.fill", "zap": "bolt.fill", "sun": "sun.max.fill", "cloud": "cloud.fill", "leaf": "leaf.fill",
        "mountain": "mountain.2.fill", "globe": "globe.americas.fill", "compass": "safari.fill", "map": "map.fill", "plane": "airplane",
        "car": "car.fill", "house": "house.fill", "church": "building.columns.fill", "cross": "cross.fill", "briefcase": "briefcase.fill",
        "calendar": "calendar", "folder": "folder.fill", "key": "key.fill", "lock": "lock.fill", "wrench": "wrench.fill",
        "hammer": "hammer.fill", "cart": "cart.fill", "gift": "gift.fill", "gem": "diamond.fill", "crown": "crown.fill",
        "coffee": "cup.and.saucer.fill", "pizza": "fork.knife", "apple": "applelogo", "dumbbell": "dumbbell.fill", "chat": "bubble.left.fill",
    ]

    static func color(_ hex: String) -> Color? {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(hex: value)
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func dataImage(_ value: String) -> NSImage? {
        if let cached = cache.object(forKey: value as NSString) { return cached }
        guard let comma = value.firstIndex(of: ","), let data = Data(base64Encoded: String(value[value.index(after: comma)...])),
              let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: value as NSString)
        return image
    }
}

/// A Cairn pixel drawing: "size:palette:cells", cells run-length encoded (3a = three of colour a, . = clear).
private struct PixelGlyph: View {
    let recipe: String

    var body: some View {
        let parts = recipe.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let side = max(4, min(32, Int(parts.first ?? "") ?? 12))
        let palette = (parts.count > 1 ? parts[1] : "").split(separator: ",").compactMap { CairnIcon.color(String($0)) }
        let cells = Self.unpack(parts.count > 2 ? parts[2] : "", total: side * side)
        Canvas { context, canvas in
            let cell = canvas.width / CGFloat(side)
            for (index, value) in cells.enumerated() where value >= 0 && value < palette.count {
                let rect = CGRect(x: CGFloat(index % side) * cell, y: CGFloat(index / side) * cell, width: cell + 0.3, height: cell + 0.3)
                context.fill(Path(rect), with: .color(palette[value]))
            }
        }
    }

    static func unpack(_ text: String, total: Int) -> [Int] {
        var out: [Int] = []
        var count = ""
        for character in text {
            if character.isNumber {
                count.append(character)
                continue
            }
            let value = character == "." ? -1 : Int(character.asciiValue ?? 97) - 97
            for _ in 0..<(Int(count) ?? 1) where out.count < total { out.append(value) }
            count = ""
        }
        return out + Array(repeating: -1, count: max(0, total - out.count))
    }
}

import SwiftUI
import AppKit

// MARK: - Now playing

struct NowPlayingWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var player = NowPlayingService.shared
    @Environment(\.widgetContext) private var context

    private var isSample: Bool { context == .gallery }
    private var track: NowPlayingService.Track? { isSample ? NowPlayingService.sample : player.track }

    var body: some View {
        Group {
            if let track {
                switch model.size {
                case .small, .large: small(track)
                case .medium: medium(track)
                }
            } else {
                WidgetMessage(symbol: "music.note", title: "Nothing playing",
                              detail: player.errorMessage == nil ? "Play something in Music or Spotify." : "Allow Home Widgets to control Music/Spotify in System Settings › Privacy › Automation.")
            }
        }
        .monitoring(NowPlayingService.shared)
    }

    private var artwork: some View {
        Group {
            if let image = player.artwork, !isSample {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.white))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Button(action: player.previous) { Image(systemName: "backward.fill") }
            Button(action: player.playPause) {
                Image(systemName: (track?.isPlaying ?? false) ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
            }
            Button(action: player.next) { Image(systemName: "forward.fill") }
        }
        .font(.system(size: 15))
        .buttonStyle(WidgetButtonStyle())
        .disabled(isSample)
    }

    private func small(_ track: NowPlayingService.Track) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                artwork.frame(width: 58, height: 58)
                Spacer()
                Image(systemName: track.player == .spotify ? "dot.radiowaves.left.and.right" : "music.note")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(track.player == .spotify ? Color.green : Color.pink)
            }
            Spacer(minLength: 0)
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(track.artist)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            controls.frame(maxWidth: .infinity)
        }
        .widgetPadding()
    }

    private func medium(_ track: NowPlayingService.Track) -> some View {
        HStack(spacing: 14) {
            artwork.frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.player == .spotify ? "SPOTIFY" : "MUSIC")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(track.player == .spotify ? Color.green : Color.pink)
                Text(track.title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                Text(track.artist)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                BarMeter(value: track.progress, color: .primary, height: 4)
                controls.frame(maxWidth: .infinity)
            }
        }
        .widgetPadding()
    }
}

// MARK: - Photo

enum PhotoKeys {
    static let path = ConfigKey("path", "")
    static let minutes = ConfigKey("minutes", 30)
}

struct PhotoWidget: View {
    @ObservedObject var model: WidgetModel
    @State private var image: NSImage?
    @State private var loadedKey = ""

    private var path: String { (model[PhotoKeys.path] as NSString).expandingTildeInPath }

    var body: some View {
        let interval = TimeInterval(max(1, model[PhotoKeys.minutes]) * 60)
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: interval)) { timeline in
            let slot = Int(timeline.date.timeIntervalSinceReferenceDate / interval)
            content
                .onAppear { load(slot: slot) }
                .onChange(of: slot) { _, newSlot in load(slot: newSlot) }
                .onChange(of: path) { _, _ in load(slot: slot) }
        }
        .widgetBackground(image == nil ? nil : CustomBackground.edgeToEdge)
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: model.size.dimensions.width, height: model.size.dimensions.height)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { if !path.isEmpty { Shell.open(path: path) } }
        } else {
            WidgetMessage(symbol: "photo.on.rectangle.angled", title: "Choose a photo",
                          detail: "Right-click › Edit Widget to pick a photo or a folder for a slideshow.")
        }
    }

    private func load(slot: Int) {
        let target = path
        guard !target.isEmpty else {
            image = nil
            return
        }
        let key = "\(target)#\(slot)"
        guard key != loadedKey else { return }
        loadedKey = key
        let pixels = Int(max(model.size.dimensions.width, model.size.dimensions.height) * 2.5)
        DispatchQueue.global(qos: .utility).async {
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: target, isDirectory: &isDirectory)
            var file = URL(fileURLWithPath: target)
            if isDirectory.boolValue {
                let images = ImageLoader.imageFiles(in: file)
                if images.isEmpty { return }
                file = images[abs(slot) % images.count]
            }
            let loaded = ImageLoader.thumbnail(at: file, maxPixel: pixels)
            DispatchQueue.main.async { image = loaded }
        }
    }
}

// MARK: - Verse of the day

enum VerseKeys {
    static let shuffle = ConfigKey("shuffle", 0)
}

struct VerseWidget: View {
    @ObservedObject var model: WidgetModel
    @Environment(\.widgetStyle) private var style

    var body: some View {
        Ticking(everySecond: false) { now in
            content(now)
        }
    }

    private func verse(for date: Date) -> Verse {
        let pool = model.size == .small ? Verses.short : Verses.all
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let index = (day + model[VerseKeys.shuffle]) % pool.count
        return pool[(index + pool.count) % pool.count]
    }

    @ViewBuilder
    private func content(_ now: Date) -> some View {
        let verse = verse(for: now)
        let textSize: CGFloat = model.size == .small ? 13 : (model.size == .medium ? 15 : 20)
        VStack(alignment: .leading, spacing: model.size == .large ? 12 : 6) {
            HStack(spacing: 5) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("VERSE OF THE DAY")
                    .font(.system(size: 10.5, weight: .bold))
                Spacer()
                Button {
                    model.config[VerseKeys.shuffle] = model[VerseKeys.shuffle] + 1
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(WidgetButtonStyle())
                .help("Show another verse")
            }
            .foregroundStyle(style.tone(Color(hex: 0xB07A3B)))
            Spacer(minLength: 0)
            Text(verse.text)
                .font(.system(size: textSize, weight: .regular, design: .serif))
                .lineSpacing(2)
                .minimumScaleFactor(0.55)
            Text("— \(verse.reference) (KJV)")
                .font(.system(size: model.size == .small ? 11 : 12.5, weight: .semibold, design: .serif))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .widgetPadding(model.size == .large ? 22 : 16)
    }
}

// MARK: - Moon phase

enum MoonPhase {
    static let synodicMonth = 29.530588853
    /// A known new moon: 2000-01-06 18:14 UTC.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    static func age(at date: Date) -> Double {
        let days = date.timeIntervalSince(referenceNewMoon) / 86_400
        let age = days.truncatingRemainder(dividingBy: synodicMonth)
        return age < 0 ? age + synodicMonth : age
    }

    static func fraction(at date: Date) -> Double { age(at: date) / synodicMonth }

    static func illumination(at date: Date) -> Double {
        (1 - cos(2 * .pi * fraction(at: date))) / 2
    }

    static func name(at date: Date) -> String {
        switch age(at: date) {
        case ..<1.85: return "New Moon"
        case ..<5.54: return "Waxing Crescent"
        case ..<9.23: return "First Quarter"
        case ..<12.92: return "Waxing Gibbous"
        case ..<16.61: return "Full Moon"
        case ..<20.30: return "Waning Gibbous"
        case ..<23.99: return "Last Quarter"
        case ..<27.68: return "Waning Crescent"
        default: return "New Moon"
        }
    }

    /// Next time the moon reaches the given phase (0 = new, 0.5 = full).
    static func next(_ phase: Double, after date: Date) -> Date {
        var delta = (phase - fraction(at: date)) * synodicMonth
        if delta <= 0.5 { delta += synodicMonth }
        return date.addingTimeInterval(delta * 86_400)
    }
}

struct MoonView: View {
    let fraction: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.fill(disc, with: .color(Color(white: 0.16)))

            let lit = (1 - cos(2 * .pi * fraction)) / 2
            let side: CGFloat = fraction < 0.5 ? 1 : -1
            let terminator = CGFloat(1 - 2 * lit)
            var shape = Path()
            let steps = 64
            for step in 0...steps {
                let angle = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
                let point = CGPoint(x: center.x + side * radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
                if step == 0 { shape.move(to: point) } else { shape.addLine(to: point) }
            }
            for step in stride(from: steps, through: 0, by: -1) {
                let angle = -Double.pi / 2 + Double.pi * Double(step) / Double(steps)
                shape.addLine(to: CGPoint(x: center.x + side * radius * CGFloat(cos(angle)) * terminator,
                                          y: center.y + radius * CGFloat(sin(angle))))
            }
            shape.closeSubpath()
            context.fill(shape, with: .radialGradient(Gradient(colors: [Color(white: 0.98), Color(white: 0.8)]),
                                                      center: CGPoint(x: center.x - radius * 0.3, y: center.y - radius * 0.3),
                                                      startRadius: 0, endRadius: radius * 1.6))
            // A few soft craters for texture.
            let craters: [(CGFloat, CGFloat, CGFloat)] = [(-0.3, -0.2, 0.16), (0.25, 0.3, 0.12), (0.1, -0.45, 0.09), (-0.15, 0.4, 0.07), (0.45, -0.05, 0.08)]
            for crater in craters {
                let rect = CGRect(x: center.x + crater.0 * radius - crater.2 * radius,
                                  y: center.y + crater.1 * radius - crater.2 * radius,
                                  width: crater.2 * radius * 2, height: crater.2 * radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.black.opacity(0.07)))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .white.opacity(0.15), radius: 8)
    }
}

struct MoonPhaseWidget: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        Ticking(everySecond: false) { now in
            switch model.size {
            case .small, .large: small(now)
            case .medium: medium(now)
            }
        }
        .environment(\.colorScheme, .dark)
        .widgetBackground(CustomBackground.gradient(Color(hex: 0x0B1026), Color(hex: 0x1F2850)))
    }

    private func small(_ now: Date) -> some View {
        VStack(spacing: 8) {
            MoonView(fraction: MoonPhase.fraction(at: now))
                .frame(width: 84, height: 84)
            Text(MoonPhase.name(at: now))
                .font(.system(size: 13, weight: .semibold))
            Text("\(Fmt.percent(MoonPhase.illumination(at: now))) illuminated")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .widgetPadding()
    }

    private func medium(_ now: Date) -> some View {
        HStack(spacing: 18) {
            MoonView(fraction: MoonPhase.fraction(at: now))
                .frame(width: 112, height: 112)
            VStack(alignment: .leading, spacing: 6) {
                Text(MoonPhase.name(at: now))
                    .font(.system(size: 17, weight: .semibold))
                Text("\(Fmt.percent(MoonPhase.illumination(at: now))) illuminated")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                LabeledRow(symbol: "circle.fill", label: "Full Moon", date: MoonPhase.next(0.5, after: now))
                LabeledRow(symbol: "circle", label: "New Moon", date: MoonPhase.next(0, after: now))
            }
        }
        .widgetPadding(16)
    }

    private struct LabeledRow: View {
        let symbol: String
        let label: String
        let date: Date

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 9)).foregroundStyle(.secondary)
                Text(label).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Spacer()
                Text(DateFormats.string(date, template: "EEEMMMd"))
                    .font(.system(size: 11.5, weight: .semibold))
            }
        }
    }
}

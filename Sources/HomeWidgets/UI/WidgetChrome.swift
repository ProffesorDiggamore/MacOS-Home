import SwiftUI
import AppKit

enum Layout {
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 14
}

/// Where a widget is being drawn. Gallery previews show sample data instead of asking for permissions.
enum WidgetContext {
    case desktop, gallery, editor
}

private struct WidgetStyleKey: EnvironmentKey {
    static let defaultValue: WidgetStyle = .glass
}

private struct WidgetContextKey: EnvironmentKey {
    static let defaultValue: WidgetContext = .desktop
}

private struct WidgetAccentKey: EnvironmentKey {
    static let defaultValue: Color = .accentColor
}

extension EnvironmentValues {
    var widgetStyle: WidgetStyle {
        get { self[WidgetStyleKey.self] }
        set { self[WidgetStyleKey.self] = newValue }
    }

    var widgetContext: WidgetContext {
        get { self[WidgetContextKey.self] }
        set { self[WidgetContextKey.self] = newValue }
    }

    var widgetAccent: Color {
        get { self[WidgetAccentKey.self] }
        set { self[WidgetAccentKey.self] = newValue }
    }
}

/// Lets a widget replace the standard background (e.g. the Weather sky or a sticky note's paper).
enum CustomBackground: Equatable {
    case sky(code: Int, isDay: Bool)
    case color(Color)
    case gradient(Color, Color)
    /// The widget draws edge-to-edge content (e.g. a photo) and needs no background.
    case edgeToEdge
}

struct CustomBackgroundKey: PreferenceKey {
    static let defaultValue: CustomBackground? = nil
    static func reduce(value: inout CustomBackground?, nextValue: () -> CustomBackground?) {
        value = value ?? nextValue()
    }
}

extension View {
    func widgetBackground(_ background: CustomBackground?) -> some View {
        preference(key: CustomBackgroundKey.self, value: background)
    }
}

/// The rounded, Apple-style container every widget sits in.
struct WidgetChrome<Content: View>: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var appearance = AppearanceSettings.shared
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.widgetContext) private var context
    private let content: Content

    init(model: WidgetModel, @ViewBuilder content: () -> Content) {
        self.model = model
        self.content = content()
    }

    private var style: WidgetStyle {
        let chosen = model.styleOverride ?? appearance.style
        return WidgetStyle.available.contains(chosen) ? chosen : .glass
    }

    private var scheme: ColorScheme {
        if style == .tinted { return .dark }
        switch appearance.scheme {
        case .light: return .light
        case .dark: return .dark
        case .system: return systemScheme
        }
    }

    var body: some View {
        let size = model.size.dimensions
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        content
            .frame(width: size.width, height: size.height)
            .backgroundPreferenceValue(CustomBackgroundKey.self) { custom in
                WidgetBackground(style: style,
                                 custom: custom,
                                 dark: scheme == .dark,
                                 opacity: appearance.backgroundOpacity,
                                 accent: appearance.accentColor,
                                 withinWindow: context != .desktop)
            }
            .clipShape(shape)
            .overlay {
                if style == .glass || style == .liquidGlass {
                    shape.strokeBorder(Color.white.opacity(scheme == .dark ? 0.10 : 0.45), lineWidth: 0.5)
                }
            }
            .shadow(color: style == .clear ? .black.opacity(0.45) : .clear, radius: 3, y: 1)
            .environment(\.colorScheme, scheme)
            .environment(\.widgetStyle, style)
            .environment(\.widgetAccent, appearance.accentColor)
            .fontDesign(appearance.font.design)
            .contextMenu {
                if context == .desktop {
                    WidgetContextMenu(model: model)
                }
            }
    }
}

struct WidgetContextMenu: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        Button("Edit “\(model.kind.title)”…") {
            AppController.shared.showSettings(widget: model.id)
        }
        if model.kind.sizes.count > 1 {
            Picker("Size", selection: $model.size) {
                ForEach(model.kind.sizes) { size in
                    Text(size.label).tag(size)
                }
            }
        }
        Picker("Style", selection: $model.styleOverride) {
            Text("Same as Other Widgets").tag(WidgetStyle?.none)
            ForEach(WidgetStyle.available) { style in
                Text(style.label).tag(WidgetStyle?.some(style))
            }
        }
        Divider()
        Button("Remove Widget") {
            AppController.shared.removeWidget(model.id)
        }
        Divider()
        Button("Add Widgets…") {
            AppController.shared.showSettings(pane: .gallery)
        }
    }
}

struct WidgetBackground: View {
    let style: WidgetStyle
    let custom: CustomBackground?
    let dark: Bool
    let opacity: Double
    let accent: Color
    let withinWindow: Bool

    var body: some View {
        if let custom {
            switch custom {
            case .sky(let code, let isDay):
                SkyGradient(code: code, isDay: isDay)
            case .color(let color):
                color
            case .gradient(let top, let bottom):
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            case .edgeToEdge:
                Color.clear
            }
        } else {
            switch style {
            case .glass:
                VisualEffectBackground(dark: dark, withinWindow: withinWindow, cornerRadius: Layout.cornerRadius)
                    .opacity(opacity)
            case .liquidGlass:
                LiquidGlassBackground(dark: dark, withinWindow: withinWindow, cornerRadius: Layout.cornerRadius)
                    .opacity(opacity)
            case .solid:
                (dark ? Color(white: 0.11) : Color.white).opacity(opacity)
            case .tinted:
                ZStack {
                    accent
                    LinearGradient(colors: [.white.opacity(0.22), .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                }
                .opacity(opacity)
            case .clear:
                Color.clear
            }
        }
    }
}

/// The weather-app style sky that changes with conditions and time of day.
struct SkyGradient: View {
    let code: Int
    let isDay: Bool

    var colors: [Color] {
        switch (WeatherCode.sky(code), isDay) {
        case (.clear, true): return [Color(hex: 0x2F7FD8), Color(hex: 0x6CB2EE)]
        case (.clear, false): return [Color(hex: 0x0B1633), Color(hex: 0x29406F)]
        case (.cloudy, true): return [Color(hex: 0x5D7E9E), Color(hex: 0x98AFC6)]
        case (.cloudy, false): return [Color(hex: 0x1D2636), Color(hex: 0x3D4B62)]
        case (.rain, true): return [Color(hex: 0x46586C), Color(hex: 0x76889C)]
        case (.rain, false): return [Color(hex: 0x161E2B), Color(hex: 0x323F52)]
        case (.snow, true): return [Color(hex: 0x7F98B4), Color(hex: 0xBCCBDB)]
        case (.snow, false): return [Color(hex: 0x2B3446), Color(hex: 0x4F5D73)]
        case (.storm, _): return [Color(hex: 0x2E3247), Color(hex: 0x575E7A)]
        case (.fog, _): return [Color(hex: 0x6E7A86), Color(hex: 0xA3ADB7)]
        }
    }

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
}

/// Frosted glass that blurs whatever is behind the widget (your wallpaper).
struct VisualEffectBackground: NSViewRepresentable {
    var dark: Bool
    var withinWindow: Bool
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: NSVisualEffectView) {
        view.blendingMode = withinWindow ? .withinWindow : .behindWindow
        view.material = dark ? .hudWindow : .popover
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        view.maskImage = Self.mask(radius: cornerRadius)
    }

    private static var masks: [CGFloat: NSImage] = [:]

    /// A stretchable rounded-rect mask; corner radii on the layer alone don't clip behind-window blur.
    static func mask(radius: CGFloat) -> NSImage {
        if let cached = masks[radius] { return cached }
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        masks[radius] = image
        return image
    }
}

/// macOS 26 Liquid Glass, with frosted glass as the fallback on older systems.
struct LiquidGlassBackground: View {
    var dark: Bool
    var withinWindow: Bool
    var cornerRadius: CGFloat

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectRepresentable(dark: dark, cornerRadius: cornerRadius)
        } else {
            VisualEffectBackground(dark: dark, withinWindow: withinWindow, cornerRadius: cornerRadius)
        }
        #else
        VisualEffectBackground(dark: dark, withinWindow: withinWindow, cornerRadius: cornerRadius)
        #endif
    }
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private struct GlassEffectRepresentable: NSViewRepresentable {
    var dark: Bool
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}
#endif

import SwiftUI
import Combine

/// One widget placed on the desktop.
final class WidgetModel: ObservableObject, Identifiable {
    let id: UUID
    let kind: WidgetKind
    @Published var size: WidgetSize
    /// Top-left corner of the widget in global screen coordinates (AppKit, y grows upward).
    @Published var topLeft: CGPoint
    @Published var config: WidgetConfig
    /// When set, overrides the global widget style for just this widget.
    @Published var styleOverride: WidgetStyle?
    /// Live, unsaved state (e.g. whether the widget is currently visible on screen).
    let runtime = WidgetRuntime()

    init(id: UUID = UUID(),
         kind: WidgetKind,
         size: WidgetSize? = nil,
         topLeft: CGPoint = .zero,
         config: WidgetConfig = WidgetConfig(),
         styleOverride: WidgetStyle? = nil) {
        self.id = id
        self.kind = kind
        let requested = size ?? kind.defaultSize
        self.size = kind.sizes.contains(requested) ? requested : kind.defaultSize
        self.topLeft = topLeft
        self.config = config
        self.styleOverride = styleOverride
    }

    /// Which layout to use (small, medium or large), whatever the exact shape.
    var family: WidgetFamily { size.family }

    var frame: CGRect {
        let dimensions = size.dimensions
        return CGRect(x: topLeft.x, y: topLeft.y - dimensions.height,
                      width: dimensions.width, height: dimensions.height)
    }

    subscript<Value: ConfigStorable>(key: ConfigKey<Value>) -> Value {
        config[key]
    }

    func binding<Value: ConfigStorable>(_ key: ConfigKey<Value>) -> Binding<Value> {
        Binding(get: { self.config[key] }, set: { self.config[key] = $0 })
    }
}

/// Things about a widget that change constantly and are never saved.
final class WidgetRuntime: ObservableObject {
    /// False while the widget is covered by other windows or hidden, so animations can pause.
    @Published var isOnScreen = true
}

/// Settings every widget has: a custom background image.
enum BackgroundKeys {
    static let image = ConfigKey("bgImage", "")
    static let dim = ConfigKey("bgDim", 0.25)
    static let blur = ConfigKey("bgBlur", 0.0)
}

/// On-disk representation of a widget.
struct WidgetRecord: Codable {
    var id: UUID
    var kind: String
    var size: String
    var x: Double
    var y: Double
    var config: WidgetConfig
    var style: String?

    init(_ model: WidgetModel) {
        id = model.id
        kind = model.kind.rawValue
        size = model.size.rawValue
        x = Double(model.topLeft.x)
        y = Double(model.topLeft.y)
        config = model.config
        style = model.styleOverride?.rawValue
    }

    func makeModel() -> WidgetModel? {
        guard let kind = WidgetKind(rawValue: kind) else { return nil }
        return WidgetModel(id: id,
                           kind: kind,
                           size: WidgetSize(rawValue: size),
                           topLeft: CGPoint(x: x, y: y),
                           config: config,
                           styleOverride: style.flatMap(WidgetStyle.init(rawValue:)))
    }
}

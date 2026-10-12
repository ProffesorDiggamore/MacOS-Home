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

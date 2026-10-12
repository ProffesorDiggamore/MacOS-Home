import Foundation

/// A single stored setting value. Widget settings are kept as a small
/// dictionary of these so new options can be added without breaking saved files.
enum ConfigValue: Codable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case strings([String])
    case date(Date)
}

protocol ConfigStorable {
    init?(configValue: ConfigValue)
    var configValue: ConfigValue { get }
}

extension Bool: ConfigStorable {
    init?(configValue: ConfigValue) {
        guard case .bool(let value) = configValue else { return nil }
        self = value
    }
    var configValue: ConfigValue { .bool(self) }
}

extension Int: ConfigStorable {
    init?(configValue: ConfigValue) {
        switch configValue {
        case .int(let value): self = value
        case .double(let value): self = Int(value)
        default: return nil
        }
    }
    var configValue: ConfigValue { .int(self) }
}

extension Double: ConfigStorable {
    init?(configValue: ConfigValue) {
        switch configValue {
        case .double(let value): self = value
        case .int(let value): self = Double(value)
        default: return nil
        }
    }
    var configValue: ConfigValue { .double(self) }
}

extension String: ConfigStorable {
    init?(configValue: ConfigValue) {
        guard case .string(let value) = configValue else { return nil }
        self = value
    }
    var configValue: ConfigValue { .string(self) }
}

extension Array: ConfigStorable where Element == String {
    init?(configValue: ConfigValue) {
        guard case .strings(let value) = configValue else { return nil }
        self = value
    }
    var configValue: ConfigValue { .strings(self) }
}

extension Date: ConfigStorable {
    init?(configValue: ConfigValue) {
        guard case .date(let value) = configValue else { return nil }
        self = value
    }
    var configValue: ConfigValue { .date(self) }
}

/// String-backed enums that can be stored as widget settings and shown in pickers.
protocol ConfigOption: ConfigStorable, RawRepresentable, CaseIterable, Identifiable, Hashable where RawValue == String {
    var label: String { get }
}

extension ConfigOption {
    init?(configValue: ConfigValue) {
        guard case .string(let raw) = configValue else { return nil }
        self.init(rawValue: raw)
    }
    var configValue: ConfigValue { .string(rawValue) }
    var id: String { rawValue }
}

/// A typed key into a widget's settings, with its default value.
struct ConfigKey<Value: ConfigStorable> {
    let name: String
    let defaultValue: Value

    init(_ name: String, _ defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

struct WidgetConfig: Codable, Equatable {
    var values: [String: ConfigValue] = [:]

    subscript<Value: ConfigStorable>(key: ConfigKey<Value>) -> Value {
        get { values[key.name].flatMap { Value(configValue: $0) } ?? key.defaultValue }
        set { values[key.name] = newValue.configValue }
    }
}

import SwiftUI
import AppKit

// MARK: - Dev toolkit

struct DevToolsWidget: View {
    @ObservedObject var model: WidgetModel
    @State private var uuid = UUID().uuidString.lowercased()
    @State private var note: String?

    var body: some View {
        Ticking(everySecond: true) { date in
            VStack(alignment: .leading, spacing: model.family == .small ? 6 : 9) {
                WidgetHeader(title: "Dev Toolkit", symbol: "curlybraces", color: .indigo, trailing: note)
                value("Unix", String(Int(date.timeIntervalSince1970)), big: model.family == .small)
                if model.family != .small {
                    value("ISO 8601", date.formatted(.iso8601))
                }
                HStack(alignment: .bottom) {
                    value("UUID", model.family == .small ? String(uuid.prefix(13)) + "…" : uuid, copy: uuid)
                    Button { uuid = UUID().uuidString.lowercased() } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(WidgetButtonStyle())
                    .help("New UUID")
                }
                if model.family == .large {
                    Divider().opacity(0.5)
                    Text("CLIPBOARD").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(ClipboardTransform.allCases) { transform in
                            Button { apply(transform) } label: {
                                Text(transform.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
                            }
                            .buttonStyle(WidgetButtonStyle())
                            .help(transform.help)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetPadding()
        }
    }

    private func value(_ title: String, _ text: String, big: Bool = false, copy: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            Text(text).font(.system(size: big ? 22 : 13.5, weight: .semibold, design: .monospaced)).fitLine(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { put(copy ?? text, note: "Copied") }
        .help("Click to copy")
    }

    private func apply(_ transform: ClipboardTransform) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            flash("Clipboard is empty")
            return
        }
        guard let result = transform.apply(text) else {
            flash("Couldn't \(transform.label)")
            return
        }
        put(result, note: "\(transform.label) ✓")
    }

    private func put(_ text: String, note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash(note)
    }

    private func flash(_ text: String) {
        note = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if note == text { note = nil } }
    }
}

/// One-click fixes for whatever text is on the clipboard.
enum ClipboardTransform: String, CaseIterable, Identifiable {
    case base64, unbase64, urlEncode, json, lower, upper

    var id: String { rawValue }
    var label: String {
        switch self {
        case .base64: return "Base64"
        case .unbase64: return "Decode"
        case .urlEncode: return "URL"
        case .json: return "JSON"
        case .lower: return "lower"
        case .upper: return "UPPER"
        }
    }
    var help: String {
        switch self {
        case .base64: return "Encode the clipboard as Base64"
        case .unbase64: return "Decode Base64 on the clipboard"
        case .urlEncode: return "Percent-encode the clipboard for a URL"
        case .json: return "Pretty-print JSON on the clipboard"
        case .lower: return "Make the clipboard lowercase"
        case .upper: return "Make the clipboard uppercase"
        }
    }

    func apply(_ text: String) -> String? {
        switch self {
        case .base64:
            return Data(text.utf8).base64EncodedString()
        case .unbase64:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Data(base64Encoded: trimmed).flatMap { String(data: $0, encoding: .utf8) }
        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?")))
        case .json:
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]) else { return nil }
            return String(data: data, encoding: .utf8)
        case .lower:
            return text.lowercased()
        case .upper:
            return text.uppercased()
        }
    }
}

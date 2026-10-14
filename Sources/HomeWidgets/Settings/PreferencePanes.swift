import SwiftUI
import AppKit

// MARK: - Appearance

struct AppearanceView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared

    var body: some View {
        Form {
            Section {
                ZStack {
                    PreviewBackdrop()
                    HStack(spacing: 14) {
                        WidgetPreview(model: PreviewModels.shared.model(for: .clock, size: .small),
                                      maxSize: CGSize(width: 130, height: 130))
                        WidgetPreview(model: PreviewModels.shared.model(for: .systemStats, size: .medium),
                                      maxSize: CGSize(width: 274, height: 130))
                        WidgetPreview(model: PreviewModels.shared.model(for: .calendar, size: .small),
                                      maxSize: CGSize(width: 130, height: 130))
                    }
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            Section("Style") {
                HStack(spacing: 12) {
                    ForEach(WidgetStyle.available) { style in
                        StyleSwatch(style: style, selected: appearance.style == style) {
                            appearance.style = style
                        }
                    }
                }
                .padding(.vertical, 4)
                Picker("Appearance", selection: $appearance.scheme) {
                    ForEach(SchemeOption.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Background opacity") {
                    Slider(value: $appearance.backgroundOpacity, in: 0.3...1)
                        .frame(maxWidth: 260)
                }
                Toggle("Drop shadow", isOn: $appearance.showShadow)
            }

            Section {
                Picker("Colors", selection: $appearance.colorMode) {
                    ForEach(WidgetColorMode.allCases) { Text($0.label).tag($0) }
                }
                switch appearance.colorMode {
                case .theme: ThemeEditor(colors: $appearance.themeColors)
                case .single: ColorChoiceRow(hex: $appearance.singleColor)
                case .original: EmptyView()
                }
                ThemePreview(look: WidgetLook(style: .glass, mode: appearance.colorMode,
                                              single: Color(hexString: appearance.singleColor) ?? .green,
                                              theme: appearance.themeColors.map { Color(hexString: $0) ?? .gray }))
            } header: {
                Text("Widget Colors")
            } footer: {
                Text("Changes every widget at once. To give one widget different colors, right-click it › Colors, or open Edit Widget.")
            }

            Section("Color & Type") {
                LabeledContent("Accent color") {
                    HStack(spacing: 8) {
                        ForEach(AccentOption.allCases) { option in
                            Button {
                                appearance.accent = option
                            } label: {
                                Circle()
                                    .fill(option == .system ? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center)) : AnyShapeStyle(option.color))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(appearance.accent == option ? 0.9 : 0), lineWidth: 2).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .help(option.label)
                        }
                    }
                }
                Picker("Font", selection: $appearance.font) {
                    ForEach(FontOption.allCases) { Text($0.label).tag($0) }
                }
            }

            Section {
                Button("Restore Default Look") { appearance.resetLook() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct StyleSwatch: View {
    let style: WidgetStyle
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    PreviewBackdrop()
                    WidgetBackground(style: style, custom: nil, dark: true, opacity: 1, accent: .blue, withinWindow: true)
                        .frame(width: 46, height: 46)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            Text("9:41")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white)
                                .shadow(color: style == .clear ? .black.opacity(0.5) : .clear, radius: 2)
                        }
                }
                .frame(width: 70, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2.5 : 1)
                )
                Text(style.label)
                    .font(.caption)
                    .foregroundStyle(selected ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General

struct GeneralView: View {
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Desktop") {
                Picker("Widgets appear", selection: $appearance.layer) {
                    ForEach(WidgetLayer.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Toggle("Lock widget positions", isOn: $appearance.locked)
                Toggle("Hide all widgets", isOn: $appearance.hidden)
                Button("Arrange Widgets Neatly") { AppController.shared.arrangeWidgets() }
            }

            Section("App") {
                Toggle("Show icon in the Dock", isOn: $appearance.showInDock)
                Toggle("Show icon in the menu bar", isOn: $appearance.showMenuBarIcon)
                if !appearance.showInDock && !appearance.showMenuBarIcon {
                    Text("To get back here later, open Home Widgets from your Applications folder or Spotlight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behavior") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LaunchAtLogin.set(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                Picker("Refresh system stats every", selection: $appearance.refreshInterval) {
                    Text("1 second").tag(1.0)
                    Text("2 seconds").tag(2.0)
                    Text("5 seconds").tag(5.0)
                }
                Picker("Temperature", selection: $appearance.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Data") {
                LabeledContent("Saved layout") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([WidgetStore.shared.directory.appendingPathComponent("widgets.json")])
                    }
                }
                Button("Reset to Default Widgets…", role: .destructive) { confirmReset = true }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Replace all widgets with the default set?", isPresented: $confirmReset) {
            Button("Reset Widgets", role: .destructive) { AppController.shared.resetWidgets() }
        } message: {
            Text("Your current widgets and their settings will be removed.")
        }
    }
}

// MARK: - About

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Home Widgets").font(.largeTitle.bold())
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Lightweight, Apple-style widgets for your Mac desktop.\nEach system monitor only runs while a widget that needs it is on screen.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Widget Gallery") { SettingsState.shared.pane = .gallery }
                Link("Source on GitHub", destination: URL(string: "https://github.com/ProffesorDiggamore/MacOS-Home")!)
            }
            .padding(.top, 6)
            Text("Weather data by Open-Meteo.com · Scripture from the King James Version")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 20)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// Quick swatches plus a full colour picker, stored as RRGGBB.
struct ColorChoiceRow: View {
    @Binding var hex: String
    private static let swatches = ["34C759", "FFCC00", "0A84FF", "FF9500", "FF3B30", "AF52DE", "FF2D55", "5AC8FA", "FFFFFF"]

    var body: some View {
        LabeledContent("Color") {
            HStack(spacing: 8) {
                ForEach(Self.swatches, id: \.self) { value in
                    Button { hex = value } label: {
                        Circle()
                            .fill(Color(hexString: value) ?? .green)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(hex == value ? 0.9 : 0.15), lineWidth: hex == value ? 2 : 1).padding(hex == value ? -3 : 0))
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("", selection: Binding(get: { Color(hexString: hex) ?? .green }, set: { hex = $0.hexString }), supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }
}


/// Presets plus one colour picker per family. Editing a slot recolours that
/// family in every widget that uses this theme.
struct ThemeEditor: View {
    @Binding var colors: [String]

    private func binding(_ slot: ThemeSlot) -> Binding<Color> {
        Binding(get: { Color(hexString: colors.indices.contains(slot.rawValue) ? colors[slot.rawValue] : "888888") ?? .gray },
                set: { color in
                    var next = colors.count == ThemeSlot.allCases.count ? colors : ThemePreset.standard
                    next[slot.rawValue] = color.hexString
                    colors = next
                })
    }

    var body: some View {
        LabeledContent("Presets") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ThemePreset.all) { preset in
                        Button { colors = preset.colors } label: {
                            VStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    ForEach(preset.colors.indices, id: \.self) { i in
                                        Circle().fill(Color(hexString: preset.colors[i]) ?? .gray).frame(width: 11, height: 11)
                                    }
                                }
                                Text(preset.name).font(.caption2).lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(colors == preset.colors ? 0.14 : 0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(colors == preset.colors ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 420)
        }
        ForEach(ThemeSlot.allCases) { slot in
            LabeledContent {
                HStack(spacing: 10) {
                    Text(slot.usedBy).font(.caption).foregroundStyle(.secondary)
                    ColorPicker("", selection: binding(slot), supportsOpacity: false).labelsHidden()
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(slot.original).frame(width: 8, height: 8).help("Originally \(slot.label.lowercased())")
                    Text(slot.label)
                }
            }
        }
    }
}

/// What the colours look like on real widget parts: CPU/GPU-style rings and a graph.
struct ThemePreview: View {
    let look: WidgetLook
    private static let samples: [(String, Color, Double)] = [
        ("CPU", .blue, 0.42), ("GPU", .purple, 0.68), ("Memory", .green, 0.55), ("Storage", .orange, 0.8), ("Alerts", .red, 0.3),
    ]

    var body: some View {
        LabeledContent("Preview") {
            HStack(spacing: 14) {
                ForEach(Self.samples, id: \.0) { name, color, value in
                    VStack(spacing: 4) {
                        ZStack {
                            Circle().stroke(look.tone(color).opacity(0.22), lineWidth: 5)
                            Circle().trim(from: 0, to: value)
                                .stroke(look.tone(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(value * 100))").font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .frame(width: 38, height: 38)
                        Text(name).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.75)))
            .environment(\.colorScheme, .dark)
        }
    }
}

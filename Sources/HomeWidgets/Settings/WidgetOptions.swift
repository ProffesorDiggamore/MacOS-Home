import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The per-widget settings shown in My Widgets.
struct WidgetOptions: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        switch model.kind {
        case .clock:
            Section("Clock") {
                Toggle("Show seconds", isOn: model.binding(ClockKeys.showSeconds))
                Toggle("24-hour time", isOn: model.binding(ClockKeys.use24Hour))
                Toggle("Show date", isOn: model.binding(ClockKeys.showDate))
                OptionPicker("Font", selection: model.binding(ClockKeys.design))
                TimeZonePicker(title: "Time zone", identifier: model.binding(ClockKeys.timeZone))
            }
        case .analogClock:
            Section("Analog Clock") {
                Toggle("Second hand", isOn: model.binding(AnalogKeys.showSeconds))
                OptionPicker("Numbers", selection: model.binding(AnalogKeys.numerals))
                OptionPicker("Face", selection: model.binding(AnalogKeys.face))
                TimeZonePicker(title: "Time zone", identifier: model.binding(AnalogKeys.timeZone))
            }
        case .worldClock:
            Section("Cities") {
                Toggle("24-hour time", isOn: model.binding(WorldClockKeys.use24Hour))
                TimeZoneListEditor(zones: model.binding(WorldClockKeys.zones))
            }
        case .calendar:
            Section("Calendar") {
                Toggle("Show upcoming events", isOn: model.binding(CalendarKeys.showEvents))
                PermissionRow(kind: .calendar)
            }
        case .countdown:
            Section("Countdown") {
                TextField("Title", text: model.binding(CountdownKeys.title))
                DatePicker("Date", selection: model.binding(CountdownKeys.target))
                OptionPicker("Icon", selection: model.binding(CountdownKeys.symbol))
            }
        case .yearProgress:
            Section {
                Text("Shows how far through the year, month, week and day you are.")
                    .foregroundStyle(.secondary)
            }
        case .systemStats, .cpu, .gpu, .memory, .systemInfo:
            Section {
                Text("Updates every \(Int(AppearanceSettings.shared.refreshInterval)) second(s). Change the refresh rate in General.")
                    .foregroundStyle(.secondary)
            }
        case .storage:
            Section {
                Text("Small shows your startup disk; Medium and Large list every connected drive.")
                    .foregroundStyle(.secondary)
            }
        case .network:
            Section("Network") {
                Toggle("Show local IP address", isOn: model.binding(NetworkKeys.showAddress))
            }
        case .battery:
            Section {
                Text("Medium size adds battery health, cycle count, power draw and temperature.")
                    .foregroundStyle(.secondary)
            }
        case .topProcesses:
            Section("Top Processes") {
                OptionPicker("Sort by", selection: model.binding(ProcessKeys.sort))
                Text("Only your own processes are visible without administrator rights.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .claude:
            Section("Claude Code") {
                Toggle("Show today's usage (Large)", isOn: model.binding(ClaudeKeys.showUsage))
                Toggle("Show finished sessions", isOn: model.binding(ClaudeKeys.showIdle))
                Text("Reads ~/.claude/projects. Click a session to jump to its terminal, or resume it if it has ended. Right-click a session for more options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .appShortcuts:
            Section("Apps") {
                Toggle("Show app names", isOn: model.binding(AppShortcutKeys.showLabels))
                AppListEditor(paths: model.binding(AppShortcutKeys.apps))
            }
        case .quickActions:
            QuickActionsOptions(model: model)
        case .reminders:
            Section("Reminders") {
                PermissionRow(kind: .reminders)
                Text("Click the circle next to a reminder to complete it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .focusTimer:
            Section("Focus Timer") {
                Stepper("Focus: \(model[FocusKeys.focusMinutes]) min", value: model.binding(FocusKeys.focusMinutes), in: 1...120)
                Stepper("Break: \(model[FocusKeys.breakMinutes]) min", value: model.binding(FocusKeys.breakMinutes), in: 1...60)
                Toggle("Send a notification when time's up", isOn: model.binding(FocusKeys.notify))
            }
        case .note:
            Section("Sticky Note") {
                OptionPicker("Color", selection: model.binding(NoteKeys.color))
                Slider(value: model.binding(NoteKeys.fontSize), in: 11...24, step: 1) {
                    Text("Text size")
                }
                TextEditor(text: model.binding(NoteKeys.text))
                    .font(.body)
                    .frame(minHeight: 80)
            }
        case .folder:
            Section("Folder") {
                PathPicker(title: "Folder", path: model.binding(FolderKeys.path), placeholder: "Downloads", chooseFolders: true)
            }
        case .weather:
            Section("Weather") {
                TextField("City", text: model.binding(WeatherKeys.city), prompt: Text("Current Location"))
                Text("Leave empty to use your current location. Powered by Open-Meteo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Sky background", isOn: model.binding(WeatherKeys.sky))
            }
        case .nowPlaying:
            Section {
                Text("Shows Music or Spotify. The first time, macOS asks to let Home Widgets control them.")
                    .foregroundStyle(.secondary)
            }
        case .photo:
            Section("Photo") {
                PathPicker(title: "Photo or folder", path: model.binding(PhotoKeys.path), placeholder: "None", chooseFolders: true, chooseFiles: true)
                Stepper("Change every \(model[PhotoKeys.minutes]) min (folders)", value: model.binding(PhotoKeys.minutes), in: 1...1440)
            }
        case .verse:
            Section {
                Text("A new King James Version verse each day. Click the arrows on the widget to see another one.")
                    .foregroundStyle(.secondary)
            }
        case .moonPhase:
            Section {
                Text("Calculated on your Mac — no internet needed.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Reusable form controls

struct OptionPicker<Option: ConfigOption>: View {
    let title: String
    @Binding var selection: Option

    init(_ title: String, selection: Binding<Option>) {
        self.title = title
        _selection = selection
    }

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                Text(option.label).tag(option)
            }
        }
    }
}

struct TimeZonePicker: View {
    let title: String
    @Binding var identifier: String
    @State private var choosing = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(identifier.isEmpty ? "This Mac (\(TimeZone.current.cityName))" : TimeZone.named(identifier).cityName)
                    .foregroundStyle(.secondary)
                Button("Change…") { choosing = true }
                if !identifier.isEmpty {
                    Button("Use Local") { identifier = "" }
                }
            }
        }
        .sheet(isPresented: $choosing) {
            TimeZoneSearch { picked in
                identifier = picked
                choosing = false
            } onCancel: {
                choosing = false
            }
        }
    }
}

struct TimeZoneListEditor: View {
    @Binding var zones: [String]
    @State private var choosing = false

    var body: some View {
        ForEach(zones, id: \.self) { zone in
            HStack {
                Text(TimeZone.named(zone).cityName)
                Spacer()
                Text(zone).font(.caption).foregroundStyle(.secondary)
                Button {
                    zones.removeAll { $0 == zone }
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Color.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .onMove { zones.move(fromOffsets: $0, toOffset: $1) }
        Button("Add City…") { choosing = true }
            .sheet(isPresented: $choosing) {
                TimeZoneSearch { picked in
                    if !zones.contains(picked) { zones.append(picked) }
                    choosing = false
                } onCancel: {
                    choosing = false
                }
            }
    }
}

struct TimeZoneSearch: View {
    let onPick: (String) -> Void
    let onCancel: () -> Void
    @State private var query = ""

    private var results: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose a City").font(.headline)
            TextField("Search (e.g. Tokyo, London, Chicago)", text: $query)
                .textFieldStyle(.roundedBorder)
            List(results, id: \.self) { identifier in
                Button {
                    onPick(identifier)
                } label: {
                    HStack {
                        Text(TimeZone.named(identifier).cityName)
                        Spacer()
                        Text(identifier).foregroundStyle(.secondary).font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 280)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .frame(width: 420, height: 420)
    }
}

struct AppListEditor: View {
    @Binding var paths: [String]

    private var effective: [String] { paths.isEmpty ? AppShortcutDefaults.paths() : paths }

    var body: some View {
        ForEach(effective, id: \.self) { path in
            HStack(spacing: 8) {
                Image(nsImage: IconCache.shared.icon(forPath: path))
                    .resizable()
                    .frame(width: 22, height: 22)
                Text(AppShortcutDefaults.displayName(path))
                Spacer()
                Button {
                    var list = effective
                    list.removeAll { $0 == path }
                    paths = list
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Color.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .onMove { source, destination in
            var list = effective
            list.move(fromOffsets: source, toOffset: destination)
            paths = list
        }
        Button("Add Apps…") { chooseApps() }
        Text("Tip: you can also drag apps from Finder onto the widget. Drag rows to reorder.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func chooseApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        var list = effective
        for url in panel.urls where !list.contains(url.path) {
            list.append(url.path)
        }
        paths = list
    }
}

struct PathPicker: View {
    let title: String
    @Binding var path: String
    var placeholder: String
    var chooseFolders = true
    var chooseFiles = false

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text(path.isEmpty ? placeholder : (path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…", action: choose)
                if !path.isEmpty {
                    Button("Reset") { path = "" }
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = chooseFolders
        panel.canChooseFiles = chooseFiles
        if chooseFiles { panel.allowedContentTypes = [.image, .folder] }
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
    }
}

struct PermissionRow: View {
    enum Kind { case calendar, reminders }
    let kind: Kind
    @ObservedObject private var service = EventService.shared

    private var access: EventService.Access {
        kind == .calendar ? service.eventAccess : service.reminderAccess
    }

    var body: some View {
        LabeledContent("Access") {
            switch access {
            case .granted:
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(Color.green)
            case .denied:
                Button("Open Privacy Settings…") {
                    Shell.openPrivacySettings(kind == .calendar ? "Privacy_Calendars" : "Privacy_Reminders")
                }
            case .unavailable:
                Text("Run the installed app (make install)").foregroundStyle(.secondary)
            case .unknown:
                Button("Allow Access…") {
                    if kind == .calendar { service.requestEventAccess() } else { service.requestReminderAccess() }
                }
            }
        }
    }
}

struct QuickActionsOptions: View {
    @ObservedObject var model: WidgetModel
    @State private var availableShortcuts: [String] = []
    @State private var loadingShortcuts = false

    private var actions: Binding<[String]> { model.binding(QuickActionKeys.actions) }
    private var shortcuts: Binding<[String]> { model.binding(QuickActionKeys.shortcuts) }

    var body: some View {
        Section("Built-in Actions") {
            ForEach(QuickAction.allCases) { action in
                Toggle(isOn: Binding(
                    get: { actions.wrappedValue.contains(action.rawValue) },
                    set: { enabled in
                        var list = actions.wrappedValue
                        if enabled { if !list.contains(action.rawValue) { list.append(action.rawValue) } }
                        else { list.removeAll { $0 == action.rawValue } }
                        actions.wrappedValue = list
                    })) {
                    Label(action.label, systemImage: action.symbol)
                }
            }
        }
        Section("Shortcuts") {
            ForEach(shortcuts.wrappedValue, id: \.self) { name in
                HStack {
                    Label(name, systemImage: "square.2.layers.3d.fill")
                    Spacer()
                    Button {
                        shortcuts.wrappedValue.removeAll { $0 == name }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(Color.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Menu("Add Shortcut") {
                if availableShortcuts.isEmpty {
                    Text(loadingShortcuts ? "Loading…" : "No shortcuts found")
                }
                ForEach(availableShortcuts.filter { !shortcuts.wrappedValue.contains($0) }, id: \.self) { name in
                    Button(name) { shortcuts.wrappedValue.append(name) }
                }
            }
            Text("Runs shortcuts from the Shortcuts app — anything from \"Start Bible Reading Playlist\" to \"Text Mom I'm on my way\".")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: loadShortcuts)
    }

    private func loadShortcuts() {
        guard availableShortcuts.isEmpty, !loadingShortcuts else { return }
        loadingShortcuts = true
        Shell.output("/usr/bin/shortcuts", ["list"]) { output in
            loadingShortcuts = false
            availableShortcuts = (output ?? "")
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
    }
}

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
                OptionPicker("Show", selection: model.binding(ClaudeKeys.display))
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
            Section("Photos") {
                ImageListEditor(paths: model.binding(PhotoKeys.images))
                PhotoFramingEditor(model: model)
                PathPicker(title: "Or show a folder", path: model.binding(PhotoKeys.path), placeholder: "None", chooseFolders: true)
                OptionPicker("Frame", selection: model.binding(PhotoKeys.frame))
                if model[PhotoKeys.frame] == .polaroid {
                    TextField("Caption", text: model.binding(PhotoKeys.caption))
                }
                Stepper("Next photo every \(model[PhotoKeys.minutes]) min", value: model.binding(PhotoKeys.minutes), in: 1...1440)
                Text("Tip: drag photos straight onto the widget. Click it to see the next one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        default:
            MoreWidgetOptions(model: model)
        }
    }
}

/// Settings for the widgets added in version 2.
struct MoreWidgetOptions: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        switch model.kind {
        case .flipClock:
            Section("Flip Clock") {
                Toggle("24-hour time", isOn: model.binding(FlipClockKeys.use24Hour))
                Toggle("Show seconds", isOn: model.binding(FlipClockKeys.showSeconds))
            }
        case .sunArc:
            Section("Sun") {
                TextField("City", text: model.binding(SunKeys.city), prompt: Text("Current Location"))
            }
        case .github:
            Section("GitHub") {
                OptionPicker("Show", selection: model.binding(GitHubKeys.section))
                AccountsLink()
            }
        case .contributions, .mail:
            Section { AccountsLink() }
        case .cairn, .slateToday, .slateStreak:
            Section("Slate vault") {
                TextField("Repo", text: model.binding(SlateKeys.repo), prompt: Text("you/notes"))
                TextField("Only this folder (optional)", text: model.binding(SlateKeys.folder), prompt: Text("All notes"))
                TextField("Daily notes folder", text: model.binding(SlateKeys.dailyFolder), prompt: Text("Daily"))
                TextField("Slate web address", text: model.binding(SlateKeys.web), prompt: Text(Slate.web))
                Text("Clicking a note opens it in Slate at this address. Clear it to open notes on GitHub instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.kind != .cairn { AccountsLink() }
            }
            Section("Look") {
                Toggle("Slate grey background", isOn: model.binding(SlateKeys.stone))
                Text("Off, the widget follows your widget style (Frosted Glass, Liquid Glass, Solid, Tinted or Clear) like every other widget.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.kind == .cairn {
                Section("Quick capture") {
                    OptionPicker("Add notes to", selection: model.binding(SlateKeys.captureTarget))
                    if model[SlateKeys.captureTarget] == .note {
                        TextField("Note path", text: model.binding(SlateKeys.inbox), prompt: Text("Inbox.md"))
                    }
                    Toggle("Add as to-dos (- [ ])", isOn: model.binding(SlateKeys.asTodo))
                }
                Section("Large size shows") {
                    OptionPicker("Content", selection: model.binding(SlateKeys.show))
                    if model[SlateKeys.show] == .pinned {
                        TextField("Pinned note path", text: model.binding(SlateKeys.pinned), prompt: Text("Projects/Plan.md"))
                    }
                    AccountsLink()
                }
            }
        case .ciRuns:
            Section("GitHub Actions") {
                TextField("Repos", text: model.binding(ActionsKeys.repos), prompt: Text("you/app, you/site"))
                Text("Separate repos with commas. Leave it empty to follow the repos you pushed to most recently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AccountsLink()
            }
        case .news:
            Section("News Feed") {
                TextField("Feed address", text: model.binding(NewsKeys.feed))
                Menu("Suggestions") {
                    Button("Apple Newsroom") { model.config[NewsKeys.feed] = "https://www.apple.com/newsroom/rss-feed.rss" }
                    Button("The Verge") { model.config[NewsKeys.feed] = "https://www.theverge.com/rss/index.xml" }
                    Button("9to5Mac") { model.config[NewsKeys.feed] = "https://9to5mac.com/feed/" }
                    Button("NASA") { model.config[NewsKeys.feed] = "https://www.nasa.gov/feed/" }
                    Button("Anthropic News") { model.config[NewsKeys.feed] = "https://www.anthropic.com/news/rss.xml" }
                    Button("GitHub Blog") { model.config[NewsKeys.feed] = "https://github.blog/feed/" }
                }
            }
        case .stocks:
            Section("Stocks") { SymbolListEditor(symbols: model.binding(QuoteKeys.stocks), placeholder: "AAPL") }
        case .crypto:
            Section("Crypto") { SymbolListEditor(symbols: model.binding(QuoteKeys.crypto), placeholder: "BTC-USD") }
        case .currency:
            Section("Currency") {
                TextField("From", text: model.binding(CurrencyKeys.base), prompt: Text("USD"))
                SymbolListEditor(symbols: model.binding(CurrencyKeys.targets), placeholder: "EUR")
                TextField("Amount", value: model.binding(CurrencyKeys.amount), format: .number)
            }
        case .sports:
            Section("Sports") {
                OptionPicker("League", selection: model.binding(SportsKeys.league))
                TextField("Only my team (optional)", text: model.binding(SportsKeys.team), prompt: Text("e.g. DAL"))
            }
        case .uptime:
            Section("Websites") { SymbolListEditor(symbols: model.binding(UptimeKeys.sites), placeholder: "example.com", uppercase: false) }
        case .serviceStatus:
            Section("Services") {
                ForEach(StatusPage.all) { page in
                    Toggle(page.name, isOn: Binding(
                        get: { model[ServiceStatusKeys.services].contains(page.id) },
                        set: { on in
                            var list = model[ServiceStatusKeys.services].filter { $0 != page.id }
                            if on { list.append(page.id) }
                            model.config[ServiceStatusKeys.services] = list
                        }))
                }
            }
        case .todo:
            Section("To-Do") {
                Button("Clear All Tasks", role: .destructive) { model.config[TodoKeys.items] = [] }
            }
        case .habits:
            Section("Habits") {
                SymbolListEditor(symbols: model.binding(HabitKeys.habits), placeholder: "New habit", uppercase: false)
                Button("Reset History", role: .destructive) { model.config[HabitKeys.log] = [] }
            }
        case .links:
            Section("Links") {
                SymbolListEditor(symbols: model.binding(LinkKeys.links), placeholder: "Name|https://example.com", uppercase: false)
                Text("Write each link as Name|address, for example YouTube|youtube.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .counter:
            Section("Counter") {
                TextField("Title", text: model.binding(CounterKeys.title))
                Stepper("Goal: \(model[CounterKeys.goal] == 0 ? "none" : String(model[CounterKeys.goal]))", value: model.binding(CounterKeys.goal), in: 0...10_000)
                Toggle("Reset every day", isOn: model.binding(CounterKeys.resetsDaily))
                Button("Reset to 0") { model.config[CounterKeys.count] = 0 }
            }
        case .sticker:
            Section("Sticker") {
                ImagePickerRow(title: "Image", path: model.binding(StickerKeys.image))
                Toggle("Fill the whole widget", isOn: model.binding(StickerKeys.fill))
                Toggle("Rounded corners", isOn: model.binding(StickerKeys.rounded))
                Toggle("Remove photo backgrounds automatically", isOn: model.binding(StickerKeys.autoCutout))
                HStack {
                    Button("Remove Background Now") { StickerCutout.run(model, force: true) }
                        .disabled(model[StickerKeys.image].isEmpty)
                    if !model[StickerKeys.original].isEmpty {
                        Button("Use Original") { StickerCutout.restoreOriginal(model) }
                    }
                }
                Text("Images that already have a transparent background are used as they are. Photos get their subject cut out (like Copy Subject in Photos) so they float right on your wallpaper. You can also drag an image onto the sticker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .text:
            Section("Text") {
                TextEditor(text: model.binding(TextKeys.text)).frame(minHeight: 60)
                OptionPicker("Font", selection: model.binding(TextKeys.font))
                OptionPicker("Color", selection: model.binding(TextKeys.color))
                OptionPicker("Alignment", selection: model.binding(TextKeys.alignment))
                Slider(value: model.binding(TextKeys.size), in: 12...72, step: 1) { Text("Size") }
            }
        case .crabPet:
            Section("Claude Crab") {
                TextField("Name", text: model.binding(CrabPetKeys.name))
                Toggle("React to Claude Code sessions", isOn: model.binding(CrabPetKeys.reactsToClaude))
            }
        default:
            V3WidgetOptions(model: model)
        }
    }
}

/// Settings for the widgets added in version 3.
struct V3WidgetOptions: View {
    @ObservedObject var model: WidgetModel

    private static let sounds = ["Glass", "Ping", "Hero", "Submarine", "Funk", "Purr", "Blow", "Bottle", "Frog", "Pop", "Sosumi", "Tink"]

    var body: some View {
        switch model.kind {
        case .monthCalendar, .upNext, .agenda:
            Section("Calendar") {
                PermissionRow(kind: .calendar)
                Text("Uses the calendars in the Calendar app (iCloud, Google, school…). Up Next shows a Join button for Zoom, Meet, Teams and FaceTime links.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .timer:
            Section("Timer") {
                TextField("Name", text: model.binding(TimerKeys.label))
                TextField("Preset minutes", text: model.binding(TimerKeys.presets), prompt: Text("1, 3, 5, 10, 15, 25"))
                Picker("Sound", selection: model.binding(TimerKeys.sound)) {
                    ForEach(Self.sounds, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: model[TimerKeys.sound]) { _, name in NSSound(named: NSSound.Name(name))?.play() }
            }
        case .webSearch:
            Section("Web Search") { OptionPicker("Search with", selection: model.binding(SearchKeys.engine)) }
        case .qrCode:
            Section("QR Code") {
                TextField("Text or link", text: model.binding(QRKeys.text), prompt: Text("Leave empty to use the clipboard"))
                Text("Click the code to copy it as a picture, or drag it into a document.").font(.caption).foregroundStyle(.secondary)
            }
        case .password:
            Section("Password") {
                Stepper("Length: \(model[PasswordKeys.length])", value: model.binding(PasswordKeys.length), in: 8...64)
                Toggle("Include symbols", isOn: model.binding(PasswordKeys.symbols))
                Toggle("Easy to type (word-style)", isOn: model.binding(PasswordKeys.memorable))
                Text("Generated on your Mac with the system's secure random generator. Nothing is saved or sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .colorPicker:
            Section("Color Picker") {
                Button("Clear History") { model.config[ColorPickerKeys.history] = [] }
            }
        case .classSchedule:
            Section("Classes") {
                TextEditor(text: model.binding(ScheduleKeys.periods))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                Toggle("No classes on weekends", isOn: model.binding(ScheduleKeys.weekdaysOnly))
                Text("One class per line, like “8:00-8:50 Math”. Times before 7 are read as afternoon.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .homework:
            Section("Homework") {
                let items = model[HomeworkKeys.items].map(HomeworkItem.init)
                if items.isEmpty {
                    Text("Nothing yet. Type in the widget: “Essay fri”, “Lab report tomorrow”, “Read ch 4 10/21”.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack {
                        Text(item.title)
                        Spacer()
                        if let due = item.due { Text(DateFormats.string(due, template: "EEEMMMd")).foregroundStyle(.secondary) }
                        Button(role: .destructive) {
                            model.config[HomeworkKeys.items] = model[HomeworkKeys.items].filter { $0 != item.raw }
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                    }
                }
            }
        case .readingPlan:
            Section("Reading Plan") {
                OptionPicker("Plan", selection: model.binding(ReadingKeys.plan))
                DatePicker("Started", selection: model.binding(ReadingKeys.start), displayedComponents: .date)
                Button("Restart From Today") {
                    model.config[ReadingKeys.start] = Calendar.current.startOfDay(for: Date())
                    model.config[ReadingKeys.done] = []
                }
                Text("Click the passage on the widget to read it on Bible Gateway (KJV).").font(.caption).foregroundStyle(.secondary)
            }
        case .airQuality:
            Section("Air Quality") {
                TextField("City", text: model.binding(AirKeys.city), prompt: Text("Current Location"))
                Text("From Open-Meteo: free, no account. Updates every 30 minutes.").font(.caption).foregroundStyle(.secondary)
            }
        case .githubRepo:
            Section("GitHub Repo") {
                TextField("Repository", text: model.binding(RepoKeys.repo), prompt: Text("owner/name"))
                Text("Public repos work without signing in. Private ones use the GitHub token from Accounts.").font(.caption).foregroundStyle(.secondary)
            }
        case .water:
            Section("Water") {
                Stepper("Daily goal: \(model[WaterKeys.goal]) glasses", value: model.binding(WaterKeys.goal), in: 1...20)
                Button("Reset Today") { model.config[WaterKeys.count] = 0 }
            }
        case .bigDate:
            Section("Big Date") { Toggle("Gradient numbers", isOn: model.binding(BigDateKeys.gradient)) }
        case .breathe:
            Section("Breathe") { OptionPicker("Rhythm", selection: model.binding(BreatheKeys.pattern)) }
        case .dotClock:
            Section("Dot Clock") {
                OptionPicker("Color", selection: model.binding(DotClockKeys.color))
                Toggle("24-hour time", isOn: model.binding(DotClockKeys.use24Hour))
                Toggle("Show seconds (medium and bigger)", isOn: model.binding(DotClockKeys.showSeconds))
            }
        case .gitStatus:
            Section("Git Status") {
                PathPicker(title: "Repository", path: model.binding(GitKeys.path), placeholder: "None", chooseFolders: true)
                OptionPicker("Click opens in", selection: model.binding(GitKeys.opener))
                Text("Checks the repo every 20 seconds while the widget is visible. Nothing is fetched from the internet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .devServers:
            Section {
                Text("Lists programs you started that are listening on a port below 49152, like Vite, Node, Python and databases. Click a row to open it in your browser.")
                    .foregroundStyle(.secondary)
            }
        case .devTools:
            Section {
                Text("Click any value to copy it. The large size adds clipboard buttons: Base64 encode or decode, URL-encode, pretty-print JSON, and change case.")
                    .foregroundStyle(.secondary)
            }
        case .onThisDay:
            Section {
                Text("Click for another event from today's date. Right-click to read it on Wikipedia.").foregroundStyle(.secondary)
            }
        case .deviceBatteries:
            Section {
                Text("Shows your Mac and any connected Bluetooth device that reports its battery, such as AirPods, Magic Mouse or a keyboard. Checks every two minutes.")
                    .foregroundStyle(.secondary)
            }
        case .recentFiles, .screenshots:
            Section {
                Text(model.kind == .screenshots
                     ? "Shows the newest files from your screenshot folder (\(RecentFilesMonitor.screenshotFolder.path)). Click to open, drag to share."
                     : "Shows files you've changed in Desktop, Documents and Downloads. macOS may ask once to allow access to those folders.")
                    .foregroundStyle(.secondary)
            }
        default:
            Section {
                Text(model.kind.summary).foregroundStyle(.secondary)
            }
        }
    }
}

/// Every widget can have its own background photo.
struct BackgroundImageSection: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        Section("Background Photo") {
            ImagePickerRow(title: "Photo", path: model.binding(BackgroundKeys.image))
            if !model[BackgroundKeys.image].isEmpty {
                Slider(value: model.binding(BackgroundKeys.dim), in: 0...0.8) { Text("Darken") }
                Slider(value: model.binding(BackgroundKeys.blur), in: 0...30) { Text("Blur") }
            }
        }
    }
}

struct AccountsLink: View {
    var body: some View {
        Button("Open Accounts…") { AppController.shared.showSettings(pane: .accounts) }
    }
}

/// Choose, paste or remove one stored image.
struct ImagePickerRow: View {
    let title: String
    @Binding var path: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                if let image = ImageStore.image(at: path, maxPixel: 80) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button("Choose…") {
                    ImageStore.choose(multiple: false) { paths in
                        if let first = paths.first { replace(with: first) }
                    }
                }
                Button("Paste") {
                    if let stored = ImageStore.importFromPasteboard() { replace(with: stored) } else { NSSound.beep() }
                }
                if !path.isEmpty {
                    Button("Remove") { replace(with: "") }
                }
            }
        }
    }

    private func replace(with newPath: String) {
        let old = path
        path = newPath
        if !old.isEmpty && old != newPath { ImageStore.removeIfStored(old) }
    }
}

/// A list of stored images with add/remove.
struct ImageListEditor: View {
    @Binding var paths: [String]

    var body: some View {
        if !paths.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(paths, id: \.self) { path in
                        ZStack(alignment: .topTrailing) {
                            if let image = ImageStore.image(at: path, maxPixel: 160) {
                                Image(nsImage: image).resizable().scaledToFill().frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Button {
                                paths.removeAll { $0 == path }
                                ImageStore.removeIfStored(path)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.white, Color.black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .padding(3)
                        }
                    }
                }
            }
        }
        HStack {
            Button("Add Photos…") {
                ImageStore.choose(multiple: true) { added in paths += added }
            }
            Button("Paste") {
                if let stored = ImageStore.importFromPasteboard() { paths.append(stored) } else { NSSound.beep() }
            }
            if !paths.isEmpty {
                Text("\(paths.count) photo\(paths.count == 1 ? "" : "s")").foregroundStyle(.secondary)
            }
        }
    }
}

/// Drag a photo to move it, pinch or use the slider to zoom, and cut its background out.
struct PhotoFramingEditor: View {
    @ObservedObject var model: WidgetModel
    @State private var index = 0
    @State private var dragStart: PhotoFraming?
    @State private var zoomStart: PhotoFraming?

    var body: some View {
        let paths = model[PhotoKeys.images]
        if !paths.isEmpty {
            let path = paths[min(index, paths.count - 1)]
            let framing = PhotoFraming.get(model, path)
            let dims = model.size.dimensions
            let scale = min(300 / dims.width, 220 / dims.height)
            let size = CGSize(width: dims.width * scale, height: dims.height * scale)
            let transparent = ImageStore.hasTransparency(path)
            let cutOriginal = PhotoCutout.original(of: path, in: model)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Position & Zoom")
                    Spacer()
                    if paths.count > 1 {
                        Stepper("Photo \(min(index, paths.count - 1) + 1) of \(paths.count)", value: $index, in: 0...(paths.count - 1))
                    }
                }
                FramedPhoto(framing: framing) {
                    if let image = ImageStore.image(at: path, maxPixel: 1200) {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: transparent && paths.count == 1 ? .fit : .fill)
                    }
                }
                .frame(width: size.width, height: size.height)
                .background(Checkerboard())
                .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius * scale, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius * scale, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
                .overlay {
                    if PhotoCutout.working.contains(path) {
                        ProgressView().controlSize(.small).padding(10).background(Circle().fill(.regularMaterial))
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let start = dragStart ?? framing
                        if dragStart == nil { dragStart = framing }
                        var next = start
                        next.x = min(1, max(-1, start.x + value.translation.width / size.width))
                        next.y = min(1, max(-1, start.y + value.translation.height / size.height))
                        PhotoFraming.set(next, for: path, in: model)
                    }
                    .onEnded { _ in dragStart = nil })
                .simultaneousGesture(MagnifyGesture()
                    .onChanged { value in
                        let start = zoomStart ?? framing
                        if zoomStart == nil { zoomStart = framing }
                        var next = start
                        next.zoom = min(4, max(0.5, start.zoom * value.magnification))
                        PhotoFraming.set(next, for: path, in: model)
                    }
                    .onEnded { _ in zoomStart = nil })
                .help("Drag to move the photo. Pinch to zoom.")
                .frame(maxWidth: .infinity)

                Slider(value: Binding(get: { framing.zoom }, set: { zoom in
                    var next = framing
                    next.zoom = zoom
                    PhotoFraming.set(next, for: path, in: model)
                }), in: 0.5...4) { Text("Zoom") }

                HStack {
                    if let cutOriginal, FileManager.default.fileExists(atPath: cutOriginal) {
                        Button("Use Original") { PhotoCutout.restore(path, in: model) }
                    } else {
                        Button(PhotoCutout.working.contains(path) ? "Removing Background…" : "Remove Background") {
                            PhotoCutout.run(path, in: model)
                        }
                        .disabled(transparent || PhotoCutout.working.contains(path))
                    }
                    Spacer()
                    Button("Reset Position") { PhotoFraming.set(PhotoFraming(), for: path, in: model) }
                        .disabled(framing == PhotoFraming())
                }
                Text(transparent && cutOriginal == nil
                     ? "This photo already has a see-through background."
                     : "Remove Background lifts out the main subject, like Copy Subject in Photos, so it floats on your wallpaper.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The grey checks behind see-through images.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.82)))
            for row in 0...Int(size.height / cell) {
                for column in 0...Int(size.width / cell) where (row + column) % 2 == 0 {
                    context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                 with: .color(Color(white: 0.92)))
                }
            }
        }
    }
}

/// Editable list of short strings (stock symbols, websites, habits…).
struct SymbolListEditor: View {
    @Binding var symbols: [String]
    var placeholder: String
    var uppercase = true
    @State private var draft = ""

    var body: some View {
        ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
            HStack {
                Text(symbol)
                Spacer()
                Button {
                    symbols.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle.fill").foregroundStyle(Color.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .onMove { symbols.move(fromOffsets: $0, toOffset: $1) }
        HStack {
            TextField("Add", text: $draft, prompt: Text(placeholder))
                .onSubmit(add)
            Button("Add", action: add).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        var value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if uppercase { value = value.uppercased() }
        guard !value.isEmpty, !symbols.contains(value) else { return }
        symbols.append(value)
        draft = ""
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

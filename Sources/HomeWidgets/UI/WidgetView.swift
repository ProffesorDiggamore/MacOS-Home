import SwiftUI

/// Picks the right view for a widget and wraps it in the shared chrome.
struct WidgetView: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var runtime: WidgetRuntime
    @ObservedObject private var appearance = AppearanceSettings.shared

    init(model: WidgetModel) {
        self.model = model
        _runtime = ObservedObject(wrappedValue: model.runtime)
    }

    var body: some View {
        WidgetChrome(model: model) {
            content
        }
        .environment(\.widgetIsVisible, runtime.isOnScreen && !appearance.hidden)
    }

    @ViewBuilder
    private var content: some View {
        switch model.kind.category {
        case .time: timeWidget
        case .planner, .tools: v3Widget
        case .system: systemWidget
        case .productivity: productivityWidget
        case .web: webWidget
        case .media: mediaWidget
        case .fun: funWidget
        }
    }

    /// Widgets added in version 3 (they also appear in the other categories' defaults).
    @ViewBuilder
    private var v3Widget: some View {
        switch model.kind {
        case .monthCalendar: MonthCalendarWidget(model: model)
        case .upNext: UpNextWidget(model: model)
        case .agenda: AgendaWidget(model: model)
        case .classSchedule: ClassScheduleWidget(model: model)
        case .homework: HomeworkWidget(model: model)
        case .readingPlan: ReadingPlanWidget(model: model)
        case .timer: TimerWidget(model: model)
        case .webSearch: WebSearchWidget(model: model)
        case .dictionary: DictionaryWidget(model: model)
        case .converter: ConverterWidget(model: model)
        case .qrCode: QRCodeWidget(model: model)
        case .password: PasswordWidget(model: model)
        case .colorPicker: ColorPickerWidget(model: model)
        case .recentFiles: RecentFilesWidget(model: model)
        case .screenshots: ScreenshotsWidget(model: model)
        case .soundOutput: SoundOutputWidget(model: model)
        case .microphone: MicrophoneWidget(model: model)
        case .keepAwake: KeepAwakeWidget(model: model)
        case .ipAddress: IPAddressWidget(model: model)
        case .internet: InternetWidget(model: model)
        case .airQuality: AirQualityWidget(model: model)
        case .githubRepo: GitHubRepoWidget(model: model)
        case .water: WaterWidget(model: model)
        case .quote: QuoteWidget(model: model)
        case .bigDate: BigDateWidget(model: model)
        case .timeRings: TimeRingsWidget(model: model)
        case .abstractArt: ArtSceneWidget(model: model, defaultStyle: .ribbons)
        case .meshGradient: MeshGradientWidget(model: model)
        case .flowingWaves: ArtSceneWidget(model: model, defaultStyle: .waves, defaultPalette: "ocean")
        case .aurora: ArtSceneWidget(model: model, defaultStyle: .aurora, defaultPalette: "sequoia")
        case .dunes: ArtSceneWidget(model: model, defaultStyle: .dunes, defaultPalette: "sunset")
        case .spirograph: SpirographWidget(model: model)
        case .orbits: ArtSceneWidget(model: model, defaultStyle: .orbitals, defaultPalette: "ventura")
        case .breathe: BreatheWidget(model: model)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var timeWidget: some View {
        switch model.kind {
        case .clock: ClockWidget(model: model)
        case .analogClock: AnalogClockWidget(model: model)
        case .worldClock: WorldClockWidget(model: model)
        case .calendar: CalendarWidget(model: model)
        case .countdown: CountdownWidget(model: model)
        case .yearProgress: YearProgressWidget(model: model)
        case .flipClock: FlipClockWidget(model: model)
        case .wordClock: WordClockWidget(model: model)
        case .binaryClock: BinaryClockWidget(model: model)
        case .stopwatch: StopwatchWidget(model: model)
        case .sunArc: SunArcWidget(model: model)
        default: v3Widget
        }
    }

    @ViewBuilder
    private var systemWidget: some View {
        switch model.kind {
        case .systemStats: SystemStatsWidget(model: model)
        case .cpu: CPUWidget(model: model)
        case .gpu: GPUWidget(model: model)
        case .memory: MemoryWidget(model: model)
        case .storage: StorageWidget(model: model)
        case .network: NetworkWidget(model: model)
        case .battery: BatteryWidget(model: model)
        case .topProcesses: TopProcessesWidget(model: model)
        case .systemInfo: SystemInfoWidget(model: model)
        case .diskActivity: DiskActivityWidget(model: model)
        case .wifi: WiFiWidget(model: model)
        case .volume: VolumeWidget(model: model)
        case .clipboard: ClipboardWidget(model: model)
        default: v3Widget
        }
    }

    @ViewBuilder
    private var productivityWidget: some View {
        switch model.kind {
        case .claude: ClaudeWidget(model: model)
        case .appShortcuts: AppShortcutsWidget(model: model)
        case .quickActions: QuickActionsWidget(model: model)
        case .reminders: RemindersWidget(model: model)
        case .focusTimer: FocusTimerWidget(model: model)
        case .note: NoteWidget(model: model)
        case .folder: FolderWidget(model: model)
        case .weather: WeatherWidget(model: model)
        case .todo: TodoWidget(model: model)
        case .habits: HabitsWidget(model: model)
        case .links: LinksWidget(model: model)
        case .calculator: CalculatorWidget(model: model)
        case .counter: CounterWidget(model: model)
        default: v3Widget
        }
    }

    @ViewBuilder
    private var webWidget: some View {
        switch model.kind {
        case .github: GitHubWidget(model: model)
        case .contributions: ContributionsWidget(model: model)
        case .cairn: CairnWidget(model: model)
        case .mail: MailWidget(model: model)
        case .news: NewsWidget(model: model)
        case .hackerNews: HackerNewsWidget(model: model)
        case .stocks: QuotesWidget(model: model, isCrypto: false)
        case .crypto: QuotesWidget(model: model, isCrypto: true)
        case .currency: CurrencyWidget(model: model)
        case .sports: SportsWidget(model: model)
        case .uptime: UptimeWidget(model: model)
        case .serviceStatus: ServiceStatusWidget(model: model)
        default: v3Widget
        }
    }

    @ViewBuilder
    private var mediaWidget: some View {
        switch model.kind {
        case .nowPlaying: NowPlayingWidget(model: model)
        case .photo: PhotoWidget(model: model)
        case .sticker: StickerWidget(model: model)
        case .text: TextWidget(model: model)
        case .verse: VerseWidget(model: model)
        case .moonPhase: MoonPhaseWidget(model: model)
        default: v3Widget
        }
    }

    @ViewBuilder
    private var funWidget: some View {
        switch model.kind {
        case .crabPet: CrabPetWidget(model: model)
        case .lavaLamp: LavaLampWidget(model: model)
        case .aquarium: AquariumWidget(model: model)
        case .digitalRain: DigitalRainWidget(model: model)
        case .nightSky: NightSkyWidget(model: model)
        case .lifeGame: LifeGameWidget(model: model)
        case .bounce: BounceWidget(model: model)
        case .moodGradient: MoodGradientWidget(model: model)
        case .palette: PaletteWidget(model: model)
        case .dice: DiceWidget(model: model)
        case .plant: PlantWidget(model: model)
        default: v3Widget
        }
    }
}

/// A scaled-down live widget for the gallery and editor.
struct WidgetPreview: View {
    @ObservedObject var model: WidgetModel
    var maxSize: CGSize
    var context: WidgetContext = .gallery

    var body: some View {
        let dimensions = model.size.dimensions
        let scale = min(1, maxSize.width / dimensions.width, maxSize.height / dimensions.height)
        WidgetView(model: model)
            .environment(\.widgetContext, context)
            .allowsHitTesting(context == .editor)
            .scaleEffect(scale)
            .frame(width: dimensions.width * scale, height: dimensions.height * scale)
    }
}

/// Keeps one preview model per widget kind/size so gallery previews don't restart constantly.
final class PreviewModels {
    static let shared = PreviewModels()
    private var models: [String: WidgetModel] = [:]

    func model(for kind: WidgetKind, size: WidgetSize) -> WidgetModel {
        let key = "\(kind.rawValue)-\(size.rawValue)"
        if let existing = models[key] { return existing }
        let model = WidgetModel(kind: kind, size: size)
        if kind == .note {
            model.config[NoteKeys.text] = "Pick up Bible study notes\nFinish math homework ✏️"
        }
        if kind == .countdown {
            model.config[CountdownKeys.title] = "Summer Break"
        }
        models[key] = model
        return model
    }
}

import SwiftUI

/// Picks the right view for a widget and wraps it in the shared chrome.
struct WidgetView: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        WidgetChrome(model: model) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.kind {
        case .clock: ClockWidget(model: model)
        case .analogClock: AnalogClockWidget(model: model)
        case .worldClock: WorldClockWidget(model: model)
        case .calendar: CalendarWidget(model: model)
        case .countdown: CountdownWidget(model: model)
        case .yearProgress: YearProgressWidget(model: model)
        case .systemStats: SystemStatsWidget(model: model)
        case .cpu: CPUWidget(model: model)
        case .gpu: GPUWidget(model: model)
        case .memory: MemoryWidget(model: model)
        case .storage: StorageWidget(model: model)
        case .network: NetworkWidget(model: model)
        case .battery: BatteryWidget(model: model)
        case .topProcesses: TopProcessesWidget(model: model)
        case .systemInfo: SystemInfoWidget(model: model)
        case .claude: ClaudeWidget(model: model)
        case .appShortcuts: AppShortcutsWidget(model: model)
        case .quickActions: QuickActionsWidget(model: model)
        case .reminders: RemindersWidget(model: model)
        case .focusTimer: FocusTimerWidget(model: model)
        case .note: NoteWidget(model: model)
        case .folder: FolderWidget(model: model)
        case .weather: WeatherWidget(model: model)
        case .nowPlaying: NowPlayingWidget(model: model)
        case .photo: PhotoWidget(model: model)
        case .verse: VerseWidget(model: model)
        case .moonPhase: MoonPhaseWidget(model: model)
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

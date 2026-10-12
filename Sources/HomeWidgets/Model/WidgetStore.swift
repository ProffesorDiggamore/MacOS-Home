import Foundation
import Combine

/// Owns the list of widgets and saves it to
/// ~/Library/Application Support/HomeWidgets/widgets.json
final class WidgetStore: ObservableObject {
    static let shared = WidgetStore()

    @Published private(set) var widgets: [WidgetModel] = []

    let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("widgets.json") }
    private var observers: [UUID: AnyCancellable] = [:]
    private var pendingSave: DispatchWorkItem?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("HomeWidgets", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Loads saved widgets. Returns false when there was nothing to load (first launch).
    @discardableResult
    func load() -> Bool {
        guard let data = try? Data(contentsOf: fileURL) else { return false }
        guard let records = try? JSONDecoder().decode([WidgetRecord].self, from: data) else {
            // Keep a copy of an unreadable file instead of silently losing it.
            let backup = directory.appendingPathComponent("widgets-unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return false
        }
        let models = records.compactMap { $0.makeModel() }
        models.forEach(observe)
        widgets = models
        return true
    }

    func add(_ model: WidgetModel) {
        observe(model)
        widgets.append(model)
        scheduleSave()
    }

    func remove(_ id: UUID) {
        observers[id] = nil
        widgets.removeAll { $0.id == id }
        scheduleSave()
    }

    func removeAll() {
        observers.removeAll()
        widgets.removeAll()
        scheduleSave()
    }

    func model(_ id: UUID) -> WidgetModel? {
        widgets.first { $0.id == id }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = widgets
        let moving = source.sorted().map { list[$0] }
        for index in source.sorted(by: >) { list.remove(at: index) }
        let insertAt = destination - source.filter { $0 < destination }.count
        list.insert(contentsOf: moving, at: max(0, min(insertAt, list.count)))
        widgets = list
        scheduleSave()
    }

    func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(widgets.map(WidgetRecord.init)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func observe(_ model: WidgetModel) {
        observers[model.id] = model.objectWillChange.sink { [weak self] _ in
            self?.scheduleSave()
        }
    }
}

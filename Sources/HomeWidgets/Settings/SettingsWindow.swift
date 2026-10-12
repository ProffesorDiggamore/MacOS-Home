import SwiftUI
import AppKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case gallery, myWidgets, appearance, general, about
    var id: String { rawValue }
}

final class SettingsState: ObservableObject {
    static let shared = SettingsState()
    @Published var pane: SettingsPane? = .gallery
    @Published var selectedWidget: UUID?
}

struct SettingsRootView: View {
    @ObservedObject private var state = SettingsState.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $state.pane) {
                Section("Widgets") {
                    Label("Widget Gallery", systemImage: "square.grid.2x2").tag(SettingsPane.gallery)
                    Label("My Widgets", systemImage: "rectangle.stack").tag(SettingsPane.myWidgets)
                }
                Section("Settings") {
                    Label("Appearance", systemImage: "paintbrush").tag(SettingsPane.appearance)
                    Label("General", systemImage: "gearshape").tag(SettingsPane.general)
                    Label("About", systemImage: "info.circle").tag(SettingsPane.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch state.pane ?? .gallery {
            case .gallery: GalleryView()
            case .myWidgets: MyWidgetsView()
            case .appearance: AppearanceView()
            case .general: GeneralView()
            case .about: AboutView()
            }
        }
        .frame(minWidth: 780, minHeight: 540)
    }
}

/// A soft wallpaper-like backdrop so glass previews have something to blur.
struct PreviewBackdrop: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x5B6FD6), Color(hex: 0x9C6ACF), Color(hex: 0xE58BA4)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                RadialGradient(colors: [Color.white.opacity(0.35), .clear], center: .topTrailing, startRadius: 10, endRadius: 260)
            )
    }
}

// MARK: - Gallery

struct GalleryView: View {
    @State private var search = ""

    private func matches(_ kind: WidgetKind) -> Bool {
        search.isEmpty
            || kind.title.localizedCaseInsensitiveContains(search)
            || kind.summary.localizedCaseInsensitiveContains(search)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Widget Gallery")
                        .font(.largeTitle.bold())
                    Text("Add widgets to your desktop. Drag them anywhere, right-click one to resize or edit it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(WidgetCategory.allCases) { category in
                    let kinds = WidgetKind.allCases.filter { $0.category == category && matches($0) }
                    if !kinds.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.title)
                                .font(.title3.weight(.semibold))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 16)], spacing: 16) {
                                ForEach(kinds) { kind in
                                    GalleryCard(kind: kind)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search widgets")
    }
}

struct GalleryCard: View {
    let kind: WidgetKind
    @State private var size: WidgetSize
    @State private var justAdded = false

    init(kind: WidgetKind) {
        self.kind = kind
        _size = State(initialValue: kind.defaultSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                PreviewBackdrop()
                WidgetPreview(model: PreviewModels.shared.model(for: kind, size: size),
                              maxSize: CGSize(width: 220, height: 170))
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(kind.tint.gradient))
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.headline)
                    Text(kind.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                if kind.sizes.count > 1 {
                    Picker("Size", selection: $size) {
                        ForEach(kind.sizes) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                Button {
                    AppController.shared.addWidget(kind, size: size)
                    justAdded = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        justAdded = false
                    }
                } label: {
                    Label(justAdded ? "Added" : "Add", systemImage: justAdded ? "checkmark" : "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - My widgets

struct MyWidgetsView: View {
    @ObservedObject private var store = WidgetStore.shared
    @ObservedObject private var state = SettingsState.shared

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $state.selectedWidget) {
                ForEach(store.widgets) { widget in
                    WidgetListRow(model: widget).tag(widget.id)
                }
                .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            }
            .frame(width: 250)
            .overlay {
                if store.widgets.isEmpty {
                    ContentUnavailableView("No Widgets", systemImage: "square.dashed",
                                           description: Text("Add some from the Widget Gallery."))
                }
            }
            Divider()
            Group {
                if let id = state.selectedWidget, let model = store.model(id) {
                    WidgetEditor(model: model).id(id)
                } else {
                    ContentUnavailableView("Select a Widget", systemImage: "cursorarrow.click.2",
                                           description: Text("Pick a widget on the left to change its size, style and options."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if state.selectedWidget == nil { state.selectedWidget = store.widgets.first?.id }
        }
    }
}

private struct WidgetListRow: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(model.kind.tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(model.kind.title)
                Text(model.size.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct WidgetEditor: View {
    @ObservedObject var model: WidgetModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ZStack {
                        PreviewBackdrop()
                        WidgetPreview(model: model, maxSize: CGSize(width: 260, height: 180), context: .editor)
                    }
                    .frame(width: 290, height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.kind.title).font(.title2.bold())
                        Text(model.kind.summary).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Layout") {
                if model.kind.sizes.count > 1 {
                    Picker("Size", selection: $model.size) {
                        ForEach(model.kind.sizes) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Picker("Style", selection: $model.styleOverride) {
                    Text("Same as Other Widgets").tag(WidgetStyle?.none)
                    ForEach(WidgetStyle.available) { Text($0.label).tag(WidgetStyle?.some($0)) }
                }
            }

            WidgetOptions(model: model)

            Section {
                Button("Remove Widget", role: .destructive) {
                    AppController.shared.removeWidget(model.id)
                }
            }
        }
        .formStyle(.grouped)
    }
}

import SwiftUI
import AppKit

enum SettingsPane: String, CaseIterable, Identifiable {
    case gallery, myWidgets, wallpapers, accounts, appearance, general, about
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
                    Label("Wallpapers", systemImage: "photo.artframe").tag(SettingsPane.wallpapers)
                }
                Section("Settings") {
                    Label("Accounts", systemImage: "person.crop.circle").tag(SettingsPane.accounts)
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
            case .wallpapers: WallpaperStudioView()
            case .accounts: AccountsView()
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

/// The gallery scrolls smoothly because every card is exactly the same height.
/// (Cards used to size themselves to their description, so the lazy grid kept
/// guessing row heights wrong and yanked the scroll position when you flicked fast.)
struct GalleryView: View {
    @State private var search = ""
    @State private var category: WidgetCategory?

    private func matches(_ kind: WidgetKind) -> Bool {
        (category == nil || kind.category == category)
            && (search.isEmpty
                || kind.title.localizedCaseInsensitiveContains(search)
                || kind.summary.localizedCaseInsensitiveContains(search))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26, pinnedViews: []) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Widget Gallery")
                            .font(.largeTitle.bold())
                        Text("Add widgets to your desktop. Drag them anywhere, right-click one to resize or edit it.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search widgets", text: $search)
                            .textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
                    .frame(width: 220)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        CategoryChip(title: "All \(WidgetKind.allCases.count)", selected: category == nil) { category = nil }
                        ForEach(WidgetCategory.allCases) { item in
                            CategoryChip(title: item.title, selected: category == item) { category = category == item ? nil : item }
                        }
                    }
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
    }
}

/// Segmented control for the usual three sizes, a menu when there are more shapes.
struct SizePicker: View {
    let sizes: [WidgetSize]
    @Binding var selection: WidgetSize

    var body: some View {
        if sizes.count <= 3 {
            Picker("Size", selection: $selection) {
                ForEach(sizes) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } else {
            Picker("Size", selection: $selection) {
                ForEach(sizes) { size in
                    Text("\(size.label)  (\(size.cells.columns)×\(size.cells.rows))").tag(size)
                }
            }
            .pickerStyle(.menu)
        }
    }
}

private struct CategoryChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(selected ? Color.accentColor : Color.primary.opacity(0.07)))
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct GalleryCard: View {
    static let height: CGFloat = 316
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
                    Text(kind.title).font(.headline).lineLimit(1)
                    Text(kind.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(height: 30, alignment: .topLeading)
                        .help(kind.summary)
                }
            }

            HStack {
                if kind.sizes.count > 1 {
                    SizePicker(sizes: kind.sizes, selection: $size)
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
        .frame(height: Self.height, alignment: .top)
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
                    SizePicker(sizes: model.kind.sizes, selection: $model.size)
                }
                Picker("Style", selection: $model.styleOverride) {
                    Text("Same as Other Widgets").tag(WidgetStyle?.none)
                    ForEach(WidgetStyle.available) { Text($0.label).tag(WidgetStyle?.some($0)) }
                }
                Picker("Colors", selection: model.binding(ColorKeys.mode)) {
                    Text("Same as Other Widgets").tag("")
                    ForEach(WidgetColorMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if model[ColorKeys.mode] == WidgetColorMode.single.rawValue {
                    ColorChoiceRow(hex: Binding(get: { model[ColorKeys.single].isEmpty ? AppearanceSettings.shared.singleColor : model[ColorKeys.single] },
                                                set: { model.config[ColorKeys.single] = $0 }))
                }
            }

            WidgetOptions(model: model)

            if ![WidgetKind.photo, .sticker].contains(model.kind) {
                BackgroundImageSection(model: model)
            }

            Section {
                Button("Remove Widget", role: .destructive) {
                    AppController.shared.removeWidget(model.id)
                }
            }
        }
        .formStyle(.grouped)
    }
}

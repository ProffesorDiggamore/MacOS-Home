import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Lists recent files in folders and watches them for changes.
final class FolderStore: ObservableObject {
    static let shared = FolderStore()

    struct Item: Identifiable, Equatable {
        let id: URL
        let name: String
        let date: Date
        let size: Int64?
        let isDirectory: Bool
    }

    @Published private(set) var items: [String: [Item]] = [:]
    @Published private(set) var errors: [String: String] = [:]

    private struct Watch {
        var count: Int
        var source: DispatchSourceFileSystemObject?
    }

    private var watches: [String: Watch] = [:]
    private let queue = DispatchQueue(label: "HomeWidgets.folders", qos: .utility)

    static var downloadsPath: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? (NSHomeDirectory() + "/Downloads")
    }

    func retain(_ path: String) {
        if var watch = watches[path] {
            watch.count += 1
            watches[path] = watch
            return
        }
        watches[path] = Watch(count: 1, source: nil)
        reload(path)
        startWatching(path)
    }

    func release(_ path: String) {
        guard var watch = watches[path] else { return }
        watch.count -= 1
        if watch.count <= 0 {
            watch.source?.cancel()
            watches[path] = nil
        } else {
            watches[path] = watch
        }
    }

    func reload(_ path: String) {
        queue.async { [weak self] in
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let keys: [URLResourceKey] = [.addedToDirectoryDateKey, .contentModificationDateKey, .fileSizeKey, .isDirectoryKey, .isPackageKey]
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
                let list = urls.compactMap { file -> Item? in
                    guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
                    let isFolder = (values.isDirectory ?? false) && !(values.isPackage ?? false)
                    return Item(id: file,
                                name: file.lastPathComponent,
                                date: values.addedToDirectoryDate ?? values.contentModificationDate ?? .distantPast,
                                size: values.fileSize.map { Int64($0) },
                                isDirectory: isFolder)
                }
                .sorted { $0.date > $1.date }
                .prefix(30)
                let result = Array(list)
                DispatchQueue.main.async {
                    self?.items[path] = result
                    self?.errors[path] = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errors[path] = "Can't read this folder. Allow access in System Settings › Privacy & Security › Files and Folders."
                }
            }
        }
    }

    private func startWatching(_ path: String) {
        queue.async { [weak self] in
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { return }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in self?.reload(path) }
            source.setCancelHandler { close(descriptor) }
            DispatchQueue.main.async {
                guard let self, var watch = self.watches[path], watch.source == nil else {
                    // Nobody needs this folder anymore; a source must be resumed before it is cancelled.
                    source.resume()
                    source.cancel()
                    return
                }
                watch.source = source
                self.watches[path] = watch
                source.resume()
            }
        }
    }
}

/// Shared cache of file and app icons.
final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]

    func icon(forPath path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        // Resolve symlinks (e.g. /Applications/Safari.app) so icons don't get an alias arrow.
        let icon = NSWorkspace.shared.icon(forFile: Self.resolved(path))
        icons[path] = icon
        return icon
    }

    private static var resolvedPaths: [String: String] = [:]

    /// The real location of a path with symlinks followed (cached).
    static func resolved(_ path: String) -> String {
        if let cached = resolvedPaths[path] { return cached }
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        resolvedPaths[path] = real
        return real
    }

    func invalidate(_ path: String) {
        icons[path] = nil
    }
}

/// Tracks which apps are running (for the little dot under app shortcuts).
final class RunningApps: ObservableObject {
    static let shared = RunningApps()
    @Published private(set) var paths: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    init() {
        update()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.update()
            })
        }
    }

    private func update() {
        paths = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.resolvingSymlinksInPath().path })
    }

    func isRunning(_ appPath: String) -> Bool {
        paths.contains(IconCache.resolved(appPath))
    }
}

/// Loads (and downsizes) images for the Photo widget.
enum ImageLoader {
    static func thumbnail(at url: URL, maxPixel: Int = 900) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    static func imageFiles(in folder: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { url in
            guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
            return type.conforms(to: .image)
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

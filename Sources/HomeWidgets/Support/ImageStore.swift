import AppKit
import CoreImage
import ImageIO
import Vision
import UniformTypeIdentifiers

/// Copies images you add ("upload") into ~/Library/Application Support/HomeWidgets/Images,
/// so widgets keep working even if you move or delete the original file.
enum ImageStore {
    static var directory: URL {
        let folder = WidgetStore.shared.directory.appendingPathComponent("Images", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static let cache = NSCache<NSString, NSImage>()

    /// Copies an image file into the store. Returns the stored path.
    static func importFile(_ url: URL) -> String? {
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension.lowercased()
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    /// Saves raw image data (from a paste or a drag from a browser). Returns the stored path.
    static func importData(_ data: Data) -> String? {
        guard let image = NSImage(data: data) else { return nil }
        return importImage(image)
    }

    static func importImage(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
        do {
            try png.write(to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    /// Imports whatever image is on the clipboard.
    static func importFromPasteboard() -> String? {
        let board = NSPasteboard.general
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           let first = urls.first {
            return importFile(first)
        }
        if let images = board.readObjects(forClasses: [NSImage.self]) as? [NSImage], let first = images.first {
            return importImage(first)
        }
        return nil
    }

    /// Loads (and caches) a downsized copy of an image for display.
    static func image(at path: String, maxPixel: Int = 1000) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let key = "\(path)#\(maxPixel)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = ImageLoader.thumbnail(at: URL(fileURLWithPath: path), maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Removes a stored copy (only files inside our Images folder are ever deleted).
    static func removeIfStored(_ path: String) {
        guard path.hasPrefix(directory.path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Shows an open panel for images. Calls back with stored paths.
    @MainActor
    static func choose(multiple: Bool, completion: @escaping ([String]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = multiple
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose images. Home Widgets keeps its own copy."
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        completion(panel.urls.compactMap(importFile))
    }

    /// Accepts dropped files or image data. Calls back on the main thread with stored paths.
    static func importDrop(_ providers: [NSItemProvider], completion: @escaping ([String]) -> Void) -> Bool {
        let usable = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) || $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }
        guard !usable.isEmpty else { return false }
        let group = DispatchGroup()
        let lock = NSLock()
        var stored: [String] = []
        func append(_ path: String?) {
            guard let path else { return }
            lock.lock()
            stored.append(path)
            lock.unlock()
        }
        for provider in usable {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                        append(importFile(url))
                    }
                    group.leave()
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    append(data.flatMap(importData))
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { completion(stored) }
        return true
    }
}

/// Generic passwords in the login Keychain (used for account tokens).
enum Keychain {
    private static let service = "HomeWidgets"

    static func get(_ account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let base: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return true }
        var add = base
        add[kSecValueData] = data
        add[kSecAttrLabel] = "Home Widgets (\(account))"
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

// MARK: - Transparency and cut-outs

extension ImageStore {
    private static var alphaCache: [String: Bool] = [:]
    private static let alphaLock = NSLock()

    /// True when the picture already has see-through areas (a PNG sticker, a cut-out).
    /// Looks at a small copy, so it's cheap even for huge photos.
    static func hasTransparency(_ path: String) -> Bool {
        alphaLock.lock()
        if let known = alphaCache[path] {
            alphaLock.unlock()
            return known
        }
        alphaLock.unlock()
        var result = false
        let url = URL(fileURLWithPath: path) as CFURL
        if let source = CGImageSourceCreateWithURL(url, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceThumbnailMaxPixelSize: 96,
           ] as CFDictionary) {
            let info = image.alphaInfo
            if info != .none && info != .noneSkipFirst && info != .noneSkipLast {
                let width = image.width, height = image.height
                var pixels = [UInt8](repeating: 255, count: width * height * 4)
                if let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    var clear = 0
                    for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] < 200 { clear += 1 }
                    result = clear > (width * height) / 50 // more than 2% see-through
                }
            }
        }
        alphaLock.lock()
        alphaCache[path] = result
        alphaLock.unlock()
        return result
    }

    /// Lifts the main subject out of a photo (the same model as Photos' "Copy Subject")
    /// and saves it as a new transparent PNG. Returns nil when nothing stands out.
    static func cutOutSubject(_ path: String) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            let url = URL(fileURLWithPath: path) as CFURL
            guard let source = CGImageSourceCreateWithURL(url, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 2048,
                  ] as CFDictionary) else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
                let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
                let ciImage = CIImage(cvPixelBuffer: buffer)
                guard let output = CIContext().createCGImage(ciImage, from: ciImage.extent) else { return nil }
                let rep = NSBitmapImageRep(cgImage: output)
                guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
                let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
                try png.write(to: destination)
                alphaLock.withLock { alphaCache[destination.path] = true }
                return destination.path
            } catch {
                return nil
            }
        }.value
    }
}

import Foundation

final class StorageMonitor: PollingMonitor {
    static let shared = StorageMonitor()

    struct Volume: Identifiable, Equatable {
        let id: String
        let name: String
        let total: Int64
        let available: Int64
        let isRoot: Bool
        let isInternal: Bool

        var used: Int64 { max(0, total - available) }
        var usage: Double { total > 0 ? Double(used) / Double(total) : 0 }
        var symbol: String { isInternal ? "internaldrive.fill" : "externaldrive.fill" }
    }

    @Published private(set) var volumes: [Volume] = []

    override var interval: TimeInterval { 30 }

    var startup: Volume? { volumes.first(where: \.isRoot) ?? volumes.first }

    override func sample() {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        var result: [Volume] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable ?? true,
                  let total = values.volumeTotalCapacity, total > 0 else { continue }
            let available = values.volumeAvailableCapacityForImportantUsage
                ?? Int64(values.volumeAvailableCapacity ?? 0)
            result.append(Volume(id: url.path,
                                 name: values.volumeName ?? url.lastPathComponent,
                                 total: Int64(total),
                                 available: available,
                                 isRoot: values.volumeIsRootFileSystem ?? (url.path == "/"),
                                 isInternal: values.volumeIsInternal ?? true))
        }
        result.sort { lhs, rhs in
            if lhs.isRoot != rhs.isRoot { return lhs.isRoot }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        if result != volumes { volumes = result }
    }
}

import Foundation
import IOKit

/// Reads GPU utilization from the IOAccelerator registry entry (works without admin rights).
final class GPUMonitor: PollingMonitor {
    static let shared = GPUMonitor()

    @Published private(set) var usage: Double = 0
    @Published private(set) var renderer: Double = 0
    @Published private(set) var tiler: Double = 0
    @Published private(set) var memoryInUse: UInt64 = 0
    @Published private(set) var history = MetricHistory()
    @Published private(set) var isAvailable = true

    private(set) var coreCount: Int?
    private(set) var name: String?

    var summary: String {
        if let coreCount { return "\(coreCount)-core GPU" }
        return name ?? "GPU"
    }

    override func sample() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            isAvailable = false
            return
        }
        defer { IOObjectRelease(iterator) }

        var best: (device: Double, renderer: Double, tiler: Double, memory: UInt64)?
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var unmanaged: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let cfProperties = unmanaged?.takeRetainedValue(),
               let properties = (cfProperties as NSDictionary) as? [String: Any] {
                if coreCount == nil, let cores = properties["gpu-core-count"] as? NSNumber {
                    coreCount = cores.intValue
                }
                if name == nil, let model = properties["model"] as? String {
                    name = model
                }
                if let stats = properties["PerformanceStatistics"] as? [String: Any] {
                    let device = Self.number(stats["Device Utilization %"]) ?? Self.number(stats["GPU Activity(%)"]) ?? 0
                    let renderer = Self.number(stats["Renderer Utilization %"]) ?? device
                    let tiler = Self.number(stats["Tiler Utilization %"]) ?? 0
                    let memory = UInt64(max(0, Self.number(stats["In use system memory"]) ?? 0))
                    if best == nil || device > best!.device {
                        best = (device, renderer, tiler, memory)
                    }
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        guard let winner = best else {
            isAvailable = false
            return
        }
        isAvailable = true
        usage = min(1, winner.device / 100)
        renderer = min(1, winner.renderer / 100)
        tiler = min(1, winner.tiler / 100)
        memoryInUse = winner.memory
        history.append(usage)
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

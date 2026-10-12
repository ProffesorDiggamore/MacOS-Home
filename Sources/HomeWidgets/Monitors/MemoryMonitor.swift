import Foundation
import Darwin

final class MemoryMonitor: PollingMonitor {
    static let shared = MemoryMonitor()

    enum Pressure {
        case normal, warning, critical

        var label: String {
            switch self {
            case .normal: return "Normal"
            case .warning: return "Elevated"
            case .critical: return "Critical"
            }
        }
    }

    let total = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var used: UInt64 = 0
    @Published private(set) var app: UInt64 = 0
    @Published private(set) var wired: UInt64 = 0
    @Published private(set) var compressed: UInt64 = 0
    @Published private(set) var cached: UInt64 = 0
    @Published private(set) var swapUsed: UInt64 = 0
    @Published private(set) var pressure: Pressure = .normal
    @Published private(set) var history = MetricHistory()

    private let host = mach_host_self()
    private lazy var pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(self.host, &size)
        return UInt64(size == 0 ? 16384 : size)
    }()

    var usage: Double { total > 0 ? Double(used) / Double(total) : 0 }

    override func sample() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(host, HOST_VM_INFO64, reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let page = pageSize
        let internal = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        app = (internal > purgeable ? internal - purgeable : 0) * page
        wired = UInt64(stats.wire_count) * page
        compressed = UInt64(stats.compressor_page_count) * page
        cached = (UInt64(stats.external_page_count) + purgeable) * page
        used = min(total, app + wired + compressed)
        history.append(usage)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapUsed = swap.xsu_used
        }

        switch Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1 {
        case 4: pressure = .critical
        case 2: pressure = .warning
        default: pressure = .normal
        }
    }
}

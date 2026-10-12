import Foundation
import Darwin

final class CPUMonitor: PollingMonitor {
    static let shared = CPUMonitor()

    private struct Ticks {
        var user: UInt32
        var system: UInt32
        var idle: UInt32
        var nice: UInt32
    }

    /// Total usage across all cores, 0...1.
    @Published private(set) var usage: Double = 0
    @Published private(set) var userShare: Double = 0
    @Published private(set) var systemShare: Double = 0
    /// Per-core usage, 0...1.
    @Published private(set) var cores: [Double] = []
    @Published private(set) var history = MetricHistory()
    @Published private(set) var loadAverage: Double = 0

    let logicalCores = ProcessInfo.processInfo.activeProcessorCount
    let performanceCores = Sysctl.int("hw.perflevel0.logicalcpu")
    let efficiencyCores = Sysctl.int("hw.perflevel1.logicalcpu")
    let chipName = Sysctl.string("machdep.cpu.brand_string") ?? "Apple Silicon"

    private var previous: [Ticks] = []
    private let host = mach_host_self()

    var coreSummary: String {
        if let performance = performanceCores, let efficiency = efficiencyCores, performance > 0, efficiency > 0 {
            return "\(performance)P + \(efficiency)E cores"
        }
        return "\(logicalCores) cores"
    }

    override func sample() {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount) == KERN_SUCCESS,
              let info = infoArray else { return }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var current: [Ticks] = []
        current.reserveCapacity(Int(cpuCount))
        for core in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * core
            current.append(Ticks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }

        let old = previous
        previous = current
        guard old.count == current.count else { return }

        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)
        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalAll: UInt64 = 0
        for (before, after) in zip(old, current) {
            let user = UInt64(after.user &- before.user) + UInt64(after.nice &- before.nice)
            let system = UInt64(after.system &- before.system)
            let idle = UInt64(after.idle &- before.idle)
            let all = user + system + idle
            perCore.append(all > 0 ? Double(user + system) / Double(all) : 0)
            totalUser += user
            totalSystem += system
            totalAll += all
        }
        guard totalAll > 0 else { return }

        cores = perCore
        userShare = Double(totalUser) / Double(totalAll)
        systemShare = Double(totalSystem) / Double(totalAll)
        usage = min(1, userShare + systemShare)
        history.append(usage)

        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) > 0 {
            loadAverage = loads[0]
        }
    }
}

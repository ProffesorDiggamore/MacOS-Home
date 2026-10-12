import AppKit
import Darwin

/// Finds the processes using the most CPU and memory (like a tiny Activity Monitor).
/// Only processes owned by you are visible without admin rights, which covers your apps.
final class ProcessMonitor: PollingMonitor {
    static let shared = ProcessMonitor()

    struct Entry: Identifiable, Equatable {
        let id: pid_t
        var name: String
        /// Percent of one core (can exceed 100 on multi-threaded work).
        let cpu: Double
        /// Memory footprint in bytes (what Activity Monitor shows).
        let memory: UInt64
        var appPath: String?
    }

    @Published private(set) var byCPU: [Entry] = []
    @Published private(set) var byMemory: [Entry] = []

    override var interval: TimeInterval { max(2, AppearanceSettings.shared.refreshInterval) }

    private let sampler = ProcessSampler()
    private let queue = DispatchQueue(label: "HomeWidgets.processes", qos: .utility)
    private var inFlight = false

    override func sample() {
        guard !inFlight else { return }
        inFlight = true
        let sampler = self.sampler
        queue.async { [weak self] in
            let snapshot = sampler.sample()
            let topCPU = Array(snapshot.sorted { $0.cpu > $1.cpu }.prefix(10))
            let topMemory = Array(snapshot.sorted { $0.memory > $1.memory }.prefix(10))
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                self.byCPU = topCPU.map(Self.resolve)
                self.byMemory = topMemory.map(Self.resolve)
            }
        }
    }

    /// Swaps raw process names for app names where possible ("Google Chrome" instead of "Google Chrome H").
    private static func resolve(_ entry: Entry) -> Entry {
        guard let app = NSRunningApplication(processIdentifier: entry.id) else { return entry }
        var resolved = entry
        resolved.name = app.localizedName ?? entry.name
        resolved.appPath = app.bundleURL?.path
        return resolved
    }
}

/// Does the actual sampling on a background queue.
final class ProcessSampler {
    private var previousCPU: [pid_t: UInt64] = [:]
    private var previousTime: UInt64 = 0
    private var names: [pid_t: String] = [:]
    private let numer: UInt64
    private let denom: UInt64

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        numer = UInt64(max(info.numer, 1))
        denom = UInt64(max(info.denom, 1))
    }

    func sample() -> [ProcessMonitor.Entry] {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = previousTime > 0 && now > previousTime ? Double(now - previousTime) : 0
        let ownPID = getpid()
        var currentCPU: [pid_t: UInt64] = [:]
        var entries: [ProcessMonitor.Entry] = []

        for pid in ProcessInfoKit.allPIDs() where pid != ownPID {
            var task = proc_taskinfo()
            let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) > 0 else { continue }

            // Task times are reported in Mach ticks; convert to nanoseconds.
            let ticks = task.pti_total_user &+ task.pti_total_system
            let nanos = ticks.multipliedReportingOverflow(by: numer).partialValue / denom
            currentCPU[pid] = nanos

            var cpu = 0.0
            if elapsed > 0, let old = previousCPU[pid], nanos >= old {
                cpu = Double(nanos - old) / elapsed * 100
            }

            var usage = rusage_info_v4()
            let hasUsage = withUnsafeMutablePointer(to: &usage) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound) == 0
                }
            }
            let footprint = hasUsage ? usage.ri_phys_footprint : task.pti_resident_size

            entries.append(ProcessMonitor.Entry(id: pid, name: name(for: pid), cpu: cpu, memory: footprint, appPath: nil))
        }

        previousCPU = currentCPU
        previousTime = now
        names = names.filter { currentCPU[$0.key] != nil }
        return entries
    }

    private func name(for pid: pid_t) -> String {
        if let cached = names[pid] { return cached }
        let name = ProcessInfoKit.name(pid) ?? "Process \(pid)"
        names[pid] = name
        return name
    }
}

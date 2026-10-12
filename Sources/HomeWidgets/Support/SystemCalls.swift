import Foundation
import Darwin

enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int32>.size {
            return Int(Int32(truncatingIfNeeded: value))
        }
        return Int(value)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cBytes: buffer)
    }

    static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &time, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
    }
}

extension String {
    /// Builds a string from a NUL-terminated byte buffer.
    init(cBytes bytes: [UInt8]) {
        let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
        self = String(decoding: bytes[..<end], as: UTF8.self)
    }

    init(cChars chars: [CChar]) {
        self.init(cBytes: chars.map { UInt8(bitPattern: $0) })
    }

    /// Builds a string from a fixed-size C char array imported as a tuple.
    init<T>(cTuple tuple: T) {
        self = withUnsafeBytes(of: tuple) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// Small helpers around the BSD process APIs.
enum ProcessInfoKit {
    static func allPIDs() -> [pid_t] {
        let estimate = Int(proc_listallpids(nil, 0))
        guard estimate > 0 else { return [] }
        let capacity = estimate + 64
        var pids = [pid_t](repeating: 0, count: capacity)
        let byteCount = Int32(capacity * MemoryLayout<pid_t>.stride)
        let found = Int(proc_listallpids(&pids, byteCount))
        guard found > 0 else { return [] }
        return pids.prefix(min(found, capacity)).filter { $0 > 0 }
    }

    static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) > 0 else { return nil }
        return info
    }

    static func name(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let size = UInt32(buffer.count)
        guard proc_name(pid, &buffer, size) > 0 else { return nil }
        return String(cChars: buffer)
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let size = UInt32(buffer.count)
        guard proc_pidpath(pid, &buffer, size) > 0 else { return nil }
        return String(cChars: buffer)
    }

    static func currentDirectory(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) > 0 else { return nil }
        let path = String(cTuple: info.pvi_cdir.vip_path)
        return path.isEmpty ? nil : path
    }

    /// The full command line of a process (arguments joined by spaces).
    static func commandLine(_ pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return "" }
        let bytes = buffer.prefix(size).map { $0 == 0 ? UInt8(ascii: " ") : $0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}

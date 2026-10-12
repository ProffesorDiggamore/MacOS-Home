import Foundation
import Darwin
import CoreWLAN

final class NetworkMonitor: PollingMonitor {
    static let shared = NetworkMonitor()

    /// Bytes per second.
    @Published private(set) var download: Double = 0
    @Published private(set) var upload: Double = 0
    @Published private(set) var downloadHistory = MetricHistory()
    @Published private(set) var uploadHistory = MetricHistory()
    @Published private(set) var connection = "Offline"
    @Published private(set) var address: String?
    @Published private(set) var sessionDownloaded: UInt64 = 0
    @Published private(set) var sessionUploaded: UInt64 = 0

    private var counters: [String: (rx: UInt32, tx: UInt32)] = [:]
    private var lastSample: Date?
    private lazy var wifiInterface: String? = CWWiFiClient.shared().interface()?.interfaceName

    var isOnline: Bool { address != nil }

    override func sample() {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return }
        defer { freeifaddrs(head) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var newCounters: [String: (rx: UInt32, tx: UInt32)] = [:]
        var primary: (name: String, ip: String)?

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            cursor = entry.pointee.ifa_next
            guard let address = entry.pointee.ifa_addr, let rawName = entry.pointee.ifa_name else { continue }
            let name = String(cString: rawName)
            guard name.hasPrefix("en") else { continue }
            let family = Int32(address.pointee.sa_family)
            let flags = Int32(bitPattern: entry.pointee.ifa_flags)

            if family == AF_LINK, let data = entry.pointee.ifa_data {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                let counter = (rx: stats.ifi_ibytes, tx: stats.ifi_obytes)
                newCounters[name] = counter
                if let old = counters[name] {
                    received += UInt64(counter.rx &- old.rx)
                    sent += UInt64(counter.tx &- old.tx)
                }
            } else if family == AF_INET, primary == nil, flags & IFF_UP != 0, flags & IFF_RUNNING != 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let hostLength = socklen_t(host.count)
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, hostLength, nil, 0, NI_NUMERICHOST) == 0 {
                    primary = (name, String(cChars: host))
                }
            }
        }

        let now = Date()
        if let last = lastSample, !counters.isEmpty {
            let elapsed = max(0.1, now.timeIntervalSince(last))
            download = Double(received) / elapsed
            upload = Double(sent) / elapsed
            sessionDownloaded += received
            sessionUploaded += sent
        }
        downloadHistory.append(download)
        uploadHistory.append(upload)
        counters = newCounters
        lastSample = now

        if let primary {
            address = primary.ip
            connection = primary.name == wifiInterface ? "Wi-Fi" : "Ethernet"
        } else {
            address = nil
            connection = "Offline"
        }
    }

    override func didStop() {
        counters = [:]
        lastSample = nil
    }
}

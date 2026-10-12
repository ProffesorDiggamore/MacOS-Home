import Foundation
import SystemConfiguration

/// Static facts about this Mac (model, chip, macOS version).
final class SystemInfoService: ObservableObject {
    static let shared = SystemInfoService()

    @Published private(set) var modelName: String
    @Published private(set) var chip: String

    let memory = ProcessInfo.processInfo.physicalMemory
    let bootTime = Sysctl.bootTime() ?? Date()
    let computerName: String = (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? Host.current().localizedName ?? "Mac"
    let userName = NSFullUserName()

    private let defaults = UserDefaults.standard

    init() {
        modelName = defaults.string(forKey: "cachedModelName") ?? "Mac"
        chip = defaults.string(forKey: "cachedChip") ?? Sysctl.string("machdep.cpu.brand_string") ?? "Apple Silicon"
        loadHardwareDetails()
    }

    var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let number = version.patchVersion > 0
            ? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            : "\(version.majorVersion).\(version.minorVersion)"
        return "macOS \(osName) \(number)"
    }

    var osName: String {
        switch ProcessInfo.processInfo.operatingSystemVersion.majorVersion {
        case 14: return "Sonoma"
        case 15: return "Sequoia"
        case 16, 26: return "Tahoe"
        default: return ""
        }
    }

    var symbolForModel: String {
        let name = modelName.lowercased()
        if name.contains("macbook") { return "laptopcomputer" }
        if name.contains("imac") { return "desktopcomputer" }
        if name.contains("mac mini") { return "macmini.fill" }
        if name.contains("studio") { return "macstudio.fill" }
        if name.contains("mac pro") { return "macpro.gen3.fill" }
        return "laptopcomputer"
    }

    private func loadHardwareDetails() {
        Shell.output("/usr/sbin/system_profiler", ["SPHardwareDataType", "-json"]) { [weak self] output in
            guard let self,
                  let data = output?.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let items = root["SPHardwareDataType"] as? [[String: Any]],
                  let hardware = items.first else { return }
            if let name = hardware["machine_name"] as? String, !name.isEmpty {
                self.modelName = name
                self.defaults.set(name, forKey: "cachedModelName")
            }
            if let chip = (hardware["chip_type"] as? String) ?? (hardware["cpu_type"] as? String), !chip.isEmpty {
                self.chip = chip
                self.defaults.set(chip, forKey: "cachedChip")
            }
        }
    }
}

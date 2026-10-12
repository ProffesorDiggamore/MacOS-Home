import Foundation
import IOKit
import IOKit.ps

final class BatteryMonitor: PollingMonitor {
    static let shared = BatteryMonitor()

    @Published private(set) var hasBattery = true
    /// Charge level, 0...1.
    @Published private(set) var level: Double = 0
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isFull = false
    /// Minutes until empty (on battery) or full (charging). Nil while macOS is still estimating.
    @Published private(set) var minutesRemaining: Int?
    @Published private(set) var cycleCount: Int?
    /// Maximum capacity compared to when new, 0...1.
    @Published private(set) var health: Double?
    @Published private(set) var temperature: Double?
    /// Positive while charging, negative while discharging.
    @Published private(set) var watts: Double?
    @Published private(set) var adapterWatts: Int?

    override var interval: TimeInterval { 5 }

    var statusText: String {
        if !hasBattery { return "No battery" }
        if isFull && isPluggedIn { return "Fully charged" }
        if isCharging {
            if let minutes = minutesRemaining { return "\(Fmt.duration(minutes: minutes)) until full" }
            return "Charging"
        }
        if isPluggedIn { return "Plugged in, not charging" }
        if let minutes = minutesRemaining { return "\(Fmt.duration(minutes: minutes)) remaining" }
        return "On battery"
    }

    override func sample() {
        readPowerSources()
        readSmartBattery()
    }

    private func readPowerSources() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            hasBattery = false
            return
        }
        var found = false
        for source in list {
            guard let cfDescription = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue(),
                  let description = (cfDescription as NSDictionary) as? [String: Any],
                  (description[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            found = true
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
            level = maximum > 0 ? min(1, current / maximum) : 0
            isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            isPluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            isFull = (description[kIOPSIsChargedKey] as? Bool) ?? (level >= 0.99)
            let key = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (description[key] as? NSNumber)?.intValue ?? -1
            minutesRemaining = minutes > 0 && (isCharging || !isPluggedIn) ? minutes : nil
            break
        }
        hasBattery = found

        if isPluggedIn, let cfDetails = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue(),
           let details = (cfDetails as NSDictionary) as? [String: Any] {
            adapterWatts = (details[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue
        } else {
            adapterWatts = nil
        }
    }

    private func readSmartBattery() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        func number(_ key: String) -> NSNumber? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
        }

        cycleCount = number("CycleCount")?.intValue
        if let design = number("DesignCapacity")?.doubleValue, design > 0,
           let maximum = (number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"))?.doubleValue {
            health = min(1, maximum / design)
        }
        if let raw = number("Temperature")?.doubleValue {
            temperature = raw / 100
        }
        if let millivolts = number("Voltage")?.doubleValue,
           let amperage = number("InstantAmperage") ?? number("Amperage") {
            let milliamps = Double(Int32(truncatingIfNeeded: amperage.int64Value))
            watts = millivolts / 1000 * milliamps / 1000
        }
    }
}

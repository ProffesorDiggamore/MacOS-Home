import SwiftUI

/// Big number + small label used across the system widgets.
private struct BigStat: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 34

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .fitLine(0.5)
    }
}

private struct LabeledValue: View {
    let label: String
    let value: String
    var color: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .lineLimit(1)
    }
}

private func percentParts(_ value: Double) -> (String, String) {
    ("\(Int((value * 100).rounded()))", "%")
}

// MARK: - CPU

struct CPUWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var cpu = CPUMonitor.shared
    @ObservedObject private var processes = ProcessMonitor.shared

    var body: some View {
        Group {
            switch model.family {
            case .small: small
            case .medium: medium
            case .large: large.monitoring(ProcessMonitor.shared)
            }
        }
        .monitoring(CPUMonitor.shared)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "CPU", symbol: "cpu", color: Palette.cpu)
            let parts = percentParts(cpu.usage)
            BigStat(value: parts.0, unit: parts.1)
            Sparkline(values: cpu.history.values, color: Palette.cpu)
                .frame(maxHeight: .infinity)
            Text(cpu.coreSummary)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fitLine()
        }
        .widgetPadding()
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "CPU", symbol: "cpu", color: Palette.cpu)
                let parts = percentParts(cpu.usage)
                BigStat(value: parts.0, unit: parts.1, size: 38)
                Spacer(minLength: 0)
                LabeledValue(label: "User", value: Fmt.percent(cpu.userShare))
                LabeledValue(label: "System", value: Fmt.percent(cpu.systemShare))
                LabeledValue(label: "Load", value: String(format: "%.2f", cpu.loadAverage))
            }
            .frame(width: 110)
            VStack(alignment: .leading, spacing: 6) {
                Sparkline(values: cpu.history.values, color: Palette.cpu)
                ColumnBars(values: cpu.cores, color: Palette.cpu, spacing: 2)
                    .frame(height: 34)
                Text("\(cpu.coreSummary) · \(cpu.chipName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fitLine(0.7)
            }
        }
        .widgetPadding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                WidgetHeader(title: "CPU", symbol: "cpu", color: Palette.cpu, trailing: cpu.chipName)
            }
            HStack(alignment: .bottom) {
                let parts = percentParts(cpu.usage)
                BigStat(value: parts.0, unit: parts.1, size: 44)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("User \(Fmt.percent(cpu.userShare)) · System \(Fmt.percent(cpu.systemShare))")
                    Text("Load \(String(format: "%.2f", cpu.loadAverage)) · \(cpu.coreSummary)")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Sparkline(values: cpu.history.values, color: Palette.cpu)
                .frame(height: 70)
            ColumnBars(values: cpu.cores, color: Palette.cpu, spacing: 3)
                .frame(height: 40)
            Divider().opacity(0.5)
            ProcessList(entries: Array(processes.byCPU.prefix(4)), metric: .cpu)
        }
        .widgetPadding(16)
    }
}

// MARK: - GPU

struct GPUWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var gpu = GPUMonitor.shared

    var body: some View {
        Group {
            if !gpu.isAvailable {
                WidgetMessage(symbol: "cube", title: "GPU stats unavailable")
            } else {
                switch model.family {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
        }
        .monitoring(GPUMonitor.shared)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "GPU", symbol: "cube.fill", color: Palette.gpu)
            let parts = percentParts(gpu.usage)
            BigStat(value: parts.0, unit: parts.1)
            Sparkline(values: gpu.history.values, color: Palette.gpu)
                .frame(maxHeight: .infinity)
            Text(gpu.summary)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fitLine()
        }
        .widgetPadding()
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                WidgetHeader(title: "GPU", symbol: "cube.fill", color: Palette.gpu)
                let parts = percentParts(gpu.usage)
                BigStat(value: parts.0, unit: parts.1, size: 38)
                Spacer(minLength: 0)
                LabeledValue(label: "Renderer", value: Fmt.percent(gpu.renderer))
                LabeledValue(label: "Tiler", value: Fmt.percent(gpu.tiler))
                if gpu.memoryInUse > 0 {
                    LabeledValue(label: "Memory", value: Fmt.memory(gpu.memoryInUse))
                }
            }
            .frame(width: 118)
            VStack(alignment: .leading, spacing: 6) {
                Sparkline(values: gpu.history.values, color: Palette.gpu)
                Text(gpu.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetPadding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "GPU", symbol: "cube.fill", color: Palette.gpu, trailing: gpu.summary)
            let parts = percentParts(gpu.usage)
            BigStat(value: parts.0, unit: parts.1, size: 48)
            Sparkline(values: gpu.history.values, color: Palette.gpu)
                .frame(maxHeight: .infinity)
            VStack(spacing: 8) {
                MeterRow(label: "Renderer", value: gpu.renderer, color: Palette.gpu)
                MeterRow(label: "Tiler", value: gpu.tiler, color: Palette.gpu)
            }
            if gpu.memoryInUse > 0 {
                LabeledValue(label: "Graphics memory in use", value: Fmt.memory(gpu.memoryInUse))
            }
        }
        .widgetPadding(16)
    }
}

private struct MeterRow: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            BarMeter(value: value, color: color, height: 6)
            Text(Fmt.percent(value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Memory

struct MemoryWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var memory = MemoryMonitor.shared
    @ObservedObject private var processes = ProcessMonitor.shared
    @Environment(\.widgetStyle) private var style

    private var pressureColor: Color {
        switch memory.pressure {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var segments: [SegmentedBar.Segment] {
        let total = Double(max(memory.total, 1))
        return [
            .init(id: "app", value: Double(memory.app) / total, color: style.tone(.green)),
            .init(id: "wired", value: Double(memory.wired) / total, color: style.tone(.orange).opacity(style == .tinted ? 0.75 : 1)),
            .init(id: "compressed", value: Double(memory.compressed) / total, color: style.tone(.purple).opacity(style == .tinted ? 0.5 : 1)),
        ]
    }

    var body: some View {
        Group {
            switch model.family {
            case .small: small
            case .medium: medium
            case .large: large.monitoring(ProcessMonitor.shared)
            }
        }
        .monitoring(MemoryMonitor.shared)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(title: "Memory", symbol: "memorychip", color: Palette.memory)
            BigStat(value: Fmt.gigabytes(memory.used), unit: "GB")
            Text("of \(Fmt.memory(memory.total)) used")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            SegmentedBar(segments: segments, height: 8)
            HStack(spacing: 4) {
                Circle().fill(pressureColor).frame(width: 6, height: 6)
                Text("Pressure: \(memory.pressure.label)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetPadding()
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(title: "Memory", symbol: "memorychip", color: Palette.memory)
                BigStat(value: Fmt.gigabytes(memory.used), unit: "GB", size: 36)
                Text("of \(Fmt.memory(memory.total))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Sparkline(values: memory.history.values, color: Palette.memory)
                    .frame(height: 34)
            }
            .frame(width: 120)
            VStack(alignment: .leading, spacing: 6) {
                SegmentedBar(segments: segments, height: 10)
                LabeledValue(label: "App", value: Fmt.memory(memory.app), color: style.tone(.green))
                LabeledValue(label: "Wired", value: Fmt.memory(memory.wired), color: style.tone(.orange))
                LabeledValue(label: "Compressed", value: Fmt.memory(memory.compressed), color: style.tone(.purple))
                LabeledValue(label: "Cached", value: Fmt.memory(memory.cached))
                LabeledValue(label: "Swap", value: Fmt.memory(memory.swapUsed))
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle().fill(pressureColor).frame(width: 6, height: 6)
                    Text("Pressure: \(memory.pressure.label)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetPadding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WidgetHeader(title: "Memory", symbol: "memorychip", color: Palette.memory, trailing: "Pressure: \(memory.pressure.label)")
            }
            HStack(alignment: .firstTextBaseline) {
                BigStat(value: Fmt.gigabytes(memory.used), unit: "GB", size: 44)
                Text("of \(Fmt.memory(memory.total))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            SegmentedBar(segments: segments, height: 12)
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    LabeledValue(label: "App", value: Fmt.memory(memory.app), color: style.tone(.green))
                    LabeledValue(label: "Wired", value: Fmt.memory(memory.wired), color: style.tone(.orange))
                }
                VStack(spacing: 4) {
                    LabeledValue(label: "Compressed", value: Fmt.memory(memory.compressed), color: style.tone(.purple))
                    LabeledValue(label: "Swap", value: Fmt.memory(memory.swapUsed))
                }
            }
            Sparkline(values: memory.history.values, color: Palette.memory)
                .frame(height: 50)
            Divider().opacity(0.5)
            ProcessList(entries: Array(processes.byMemory.prefix(4)), metric: .memory)
        }
        .widgetPadding(16)
    }
}

// MARK: - Storage

struct StorageWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var storage = StorageMonitor.shared
    @Environment(\.widgetStyle) private var style

    var body: some View {
        Group {
            if let startup = storage.startup {
                switch model.family {
                case .small: small(startup)
                case .medium: list(limit: 3)
                case .large: list(limit: 7)
                }
            } else {
                WidgetMessage(symbol: "internaldrive", title: "Reading disks…")
            }
        }
        .monitoring(StorageMonitor.shared)
    }

    private func small(_ volume: StorageMonitor.Volume) -> some View {
        VStack(spacing: 8) {
            WidgetHeader(title: "Storage", symbol: "internaldrive", color: Palette.disk)
            RingGauge(value: volume.usage, color: Palette.disk, lineWidth: 9) {
                VStack(spacing: 0) {
                    Text(Fmt.disk(volume.available))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .fitLine(0.6)
                    Text("free")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
            }
            Text(volume.name)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fitLine()
        }
        .widgetPadding()
    }

    private func list(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Storage", symbol: "internaldrive", color: Palette.disk)
            ForEach(storage.volumes.prefix(limit)) { volume in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: volume.symbol)
                            .foregroundStyle(.secondary)
                        Text(volume.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Fmt.disk(volume.available)) free of \(Fmt.disk(volume.total))")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    BarMeter(value: volume.usage, color: volume.usage > 0.9 ? .red : Palette.disk, height: 7)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }
}

// MARK: - Network

enum NetworkKeys {
    static let showAddress = ConfigKey("showAddress", true)
}

struct NetworkWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var network = NetworkMonitor.shared

    private var peak: Double {
        max(network.downloadHistory.peak, network.uploadHistory.peak, 50_000)
    }

    var body: some View {
        Group {
            switch model.family {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .monitoring(NetworkMonitor.shared)
    }

    private var header: some View {
        WidgetHeader(title: network.connection, symbol: network.connection == "Wi-Fi" ? "wifi" : "network",
                     color: Palette.download,
                     trailing: model[NetworkKeys.showAddress] ? network.address : nil)
    }

    private func rate(_ symbol: String, _ value: Double, _ color: Color, size: CGFloat) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.6, weight: .bold))
                .foregroundStyle(color)
            Text(Fmt.rate(value))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .fitLine(0.6)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: network.connection, symbol: network.connection == "Wi-Fi" ? "wifi" : "network", color: Palette.download)
            rate("arrow.down", network.download, Palette.download, size: 19)
            rate("arrow.up", network.upload, Palette.upload, size: 19)
            ZStack {
                Sparkline(values: network.downloadHistory.values, color: Palette.download, maxValue: peak)
                Sparkline(values: network.uploadHistory.values, color: Palette.upload, maxValue: peak, lineWidth: 1.2)
            }
        }
        .widgetPadding()
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Download").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    rate("arrow.down", network.download, Palette.download, size: 20)
                    Sparkline(values: network.downloadHistory.values, color: Palette.download, maxValue: peak)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Upload").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.secondary)
                    rate("arrow.up", network.upload, Palette.upload, size: 20)
                    Sparkline(values: network.uploadHistory.values, color: Palette.upload, maxValue: peak)
                }
            }
        }
        .widgetPadding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 16) {
                rate("arrow.down", network.download, Palette.download, size: 26)
                rate("arrow.up", network.upload, Palette.upload, size: 26)
            }
            ZStack {
                Sparkline(values: network.downloadHistory.values, color: Palette.download, maxValue: peak)
                Sparkline(values: network.uploadHistory.values, color: Palette.upload, maxValue: peak, lineWidth: 1.2)
            }
            .frame(maxHeight: .infinity)
            LabeledValue(label: "Downloaded while watching", value: Fmt.disk(Int64(clamping: network.sessionDownloaded)), color: Palette.download)
            LabeledValue(label: "Uploaded while watching", value: Fmt.disk(Int64(clamping: network.sessionUploaded)), color: Palette.upload)
        }
        .widgetPadding(16)
    }
}

// MARK: - System stats dashboard

struct SystemStatsWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var cpu = CPUMonitor.shared
    @ObservedObject private var gpu = GPUMonitor.shared
    @ObservedObject private var memory = MemoryMonitor.shared
    @ObservedObject private var storage = StorageMonitor.shared
    @ObservedObject private var battery = BatteryMonitor.shared

    private struct Stat: Identifiable {
        let id: String
        let symbol: String
        let value: Double
        let color: Color
        let caption: String
    }

    private var stats: [Stat] {
        [
            Stat(id: "CPU", symbol: "cpu", value: cpu.usage, color: Palette.cpu, caption: Fmt.percent(cpu.usage)),
            Stat(id: "GPU", symbol: "cube.fill", value: gpu.usage, color: Palette.gpu, caption: Fmt.percent(gpu.usage)),
            Stat(id: "Memory", symbol: "memorychip", value: memory.usage, color: Palette.memory, caption: Fmt.percent(memory.usage)),
            Stat(id: "Disk", symbol: "internaldrive", value: storage.startup?.usage ?? 0, color: Palette.disk,
                 caption: Fmt.percent(storage.startup?.usage ?? 0)),
        ]
    }

    var body: some View {
        Group {
            switch model.family {
            case .small: small
            case .medium: medium
            case .large: large.monitoring(BatteryMonitor.shared)
            }
        }
        .monitoring(CPUMonitor.shared, GPUMonitor.shared, MemoryMonitor.shared, StorageMonitor.shared)
    }

    private func ring(_ stat: Stat, size: CGFloat, lineWidth: CGFloat) -> some View {
        RingGauge(value: stat.value, color: stat.color, lineWidth: lineWidth) {
            Image(systemName: stat.symbol)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
    }

    private var small: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(stats) { stat in
                VStack(spacing: 3) {
                    ring(stat, size: 46, lineWidth: 5.5)
                    Text(stat.caption)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                }
            }
        }
        .widgetPadding(12)
    }

    private var medium: some View {
        HStack(spacing: 0) {
            ForEach(stats) { stat in
                VStack(spacing: 6) {
                    ring(stat, size: 58, lineWidth: 6.5)
                    Text(stat.caption)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(stat.id)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .widgetPadding()
    }

    private var large: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                ForEach(stats) { stat in
                    VStack(spacing: 6) {
                        ring(stat, size: 62, lineWidth: 7)
                        Text(stat.caption)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(stat.id)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("CPU").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                Sparkline(values: cpu.history.values, color: Palette.cpu)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("GPU").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                Sparkline(values: gpu.history.values, color: Palette.gpu)
            }
            if battery.hasBattery {
                HStack(spacing: 8) {
                    Image(systemName: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .foregroundStyle(battery.level < 0.2 ? Color.red : Color.green)
                    Text("\(Fmt.percent(battery.level)) · \(battery.statusText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .widgetPadding(16)
    }
}

// MARK: - Battery

struct BatteryWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var battery = BatteryMonitor.shared
    @ObservedObject private var system = SystemInfoService.shared

    private var color: Color {
        if battery.isCharging || battery.isPluggedIn { return .green }
        if battery.level < 0.1 { return .red }
        if battery.level < 0.2 { return .orange }
        return .green
    }

    var body: some View {
        Group {
            if !battery.hasBattery {
                WidgetMessage(symbol: "powerplug.fill", title: "No battery", detail: "This Mac runs on power adapter only.")
            } else {
                switch model.family {
                case .small, .large: small
                case .medium: medium
                }
            }
        }
        .monitoring(BatteryMonitor.shared)
    }

    private var ring: some View {
        RingGauge(value: battery.level, color: color, lineWidth: 9) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: system.symbolForModel)
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.secondary)
                if battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.green)
                        .offset(x: 8, y: -8)
                }
            }
        }
    }

    private var small: some View {
        VStack(spacing: 8) {
            ring
                .frame(width: 96, height: 96)
            Text(Fmt.percent(battery.level))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(battery.statusText)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
                .fitLine(0.7)
        }
        .widgetPadding(12)
    }

    private var medium: some View {
        HStack(spacing: 18) {
            VStack(spacing: 6) {
                ring.frame(width: 92, height: 92)
                Text(Fmt.percent(battery.level))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(battery.statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .fitLine(0.7)
                if let health = battery.health {
                    LabeledValue(label: "Health", value: Fmt.percent(health))
                }
                if let cycles = battery.cycleCount {
                    LabeledValue(label: "Cycles", value: "\(cycles)")
                }
                if let watts = battery.watts, abs(watts) > 0.1 {
                    LabeledValue(label: watts > 0 ? "Charging at" : "Using", value: String(format: "%.1f W", abs(watts)))
                }
                if let adapter = battery.adapterWatts {
                    LabeledValue(label: "Adapter", value: "\(adapter) W")
                }
                if let temperature = battery.temperature {
                    LabeledValue(label: "Temperature", value: Fmt.temperature(celsius: temperature))
                }
            }
        }
        .widgetPadding(16)
    }
}

// MARK: - Top processes

enum ProcessKeys {
    static let sort = ConfigKey("sort", ProcessSort.cpu)
}

enum ProcessSort: String, ConfigOption {
    case cpu, memory
    var label: String { self == .cpu ? "CPU" : "Memory" }
}

struct ProcessList: View {
    let entries: [ProcessMonitor.Entry]
    let metric: ProcessSort

    var body: some View {
        VStack(spacing: 6) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Group {
                        if let path = entry.appPath {
                            Image(nsImage: IconCache.shared.icon(forPath: path))
                                .resizable()
                        } else {
                            Image(systemName: "gearshape.fill")
                                .resizable()
                                .scaledToFit()
                                .padding(2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    Text(entry.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(metric == .cpu ? String(format: "%.1f%%", entry.cpu) : Fmt.memory(entry.memory))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if entries.isEmpty {
                Text("Measuring…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TopProcessesWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var processes = ProcessMonitor.shared

    var body: some View {
        let sort = model[ProcessKeys.sort]
        let entries = sort == .cpu ? processes.byCPU : processes.byMemory
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "Top Processes", symbol: "list.bullet.rectangle", color: .gray,
                         trailing: sort == .cpu ? "by CPU" : "by Memory")
            ProcessList(entries: Array(entries.prefix(model.family == .large ? 10 : 4)), metric: sort)
            Spacer(minLength: 0)
        }
        .widgetPadding()
        .monitoring(ProcessMonitor.shared)
    }
}

// MARK: - About this Mac

struct SystemInfoWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var info = SystemInfoService.shared

    var body: some View {
        Ticking(everySecond: false) { now in
            switch model.family {
            case .small, .large: small(now)
            case .medium: medium(now)
            }
        }
    }

    private func small(_ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(systemName: "apple.logo")
                .font(.system(size: 22))
            Spacer(minLength: 0)
            Text(info.modelName)
                .font(.system(size: 15, weight: .bold))
                .fitLine(0.6)
            Text(info.chip)
                .font(.system(size: 12, weight: .medium))
                .fitLine(0.6)
            Text(info.osVersion)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fitLine(0.6)
            Text("Up \(Fmt.uptime(since: info.bootTime, now: now))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetPadding(16)
    }

    private func medium(_ now: Date) -> some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: info.symbolForModel)
                    .font(.system(size: 54, weight: .thin))
                Image(systemName: "apple.logo")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 90)
            VStack(alignment: .leading, spacing: 4) {
                Text(info.computerName)
                    .font(.system(size: 14, weight: .bold))
                    .fitLine(0.6)
                LabeledValue(label: "Model", value: info.modelName)
                LabeledValue(label: "Chip", value: info.chip)
                LabeledValue(label: "Memory", value: Fmt.memory(info.memory))
                LabeledValue(label: "macOS", value: info.osVersion.replacingOccurrences(of: "macOS ", with: ""))
                LabeledValue(label: "Uptime", value: Fmt.uptime(since: info.bootTime, now: now))
            }
        }
        .widgetPadding(16)
    }
}

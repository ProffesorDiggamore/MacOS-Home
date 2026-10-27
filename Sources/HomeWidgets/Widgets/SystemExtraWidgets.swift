import SwiftUI
import AppKit
import IOKit.pwr_mgt
import Network
import CoreAudio

// MARK: - Sound output

struct SoundOutputWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var devices = AudioDevicesMonitor.shared
    @ObservedObject private var volume = VolumeMonitor.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    private var outputs: [AudioSystem.Device] {
        if context == .gallery {
            return [AudioSystem.Device(id: 1, name: "MacBook Pro Speakers", hasOutput: true, hasInput: false, transport: 0),
                    AudioSystem.Device(id: 2, name: "AirPods Pro", hasOutput: true, hasInput: true, transport: kAudioDeviceTransportTypeBluetooth),
                    AudioSystem.Device(id: 3, name: "Studio Display", hasOutput: true, hasInput: false, transport: kAudioDeviceTransportTypeUSB)]
        }
        return devices.devices.filter(\.hasOutput)
    }

    private var currentID: AudioDeviceID? { context == .gallery ? 2 : devices.output }

    var body: some View {
        let current = outputs.first { $0.id == currentID }
        let tone = style.tone(.pink)
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Sound Output", symbol: "hifispeaker.2.fill", color: .pink)
            if model.family == .small {
                Menu {
                    ForEach(outputs) { device in
                        Button { devices.select(device.id, input: false) } label: {
                            Label(device.name, systemImage: device.id == currentID ? "checkmark" : device.symbol)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: current?.symbol ?? "speaker.slash.fill").font(.system(size: 26)).foregroundStyle(tone)
                        Text(current?.name ?? "No output").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            } else {
                VStack(spacing: 3) {
                    ForEach(outputs.prefix(model.family == .large ? 8 : 3)) { device in
                        Button { devices.select(device.id, input: false) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: device.symbol).frame(width: 18)
                                Text(device.name).font(.system(size: 12, weight: device.id == currentID ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 4)
                                if device.id == currentID { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(tone) }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7).fill(device.id == currentID ? tone.opacity(0.15) : .clear))
                        }
                        .buttonStyle(WidgetButtonStyle())
                    }
                }
            }
            Spacer(minLength: 0)
            if volume.hasVolume || context == .gallery {
                HStack(spacing: 6) {
                    Button(action: volume.toggleMute) {
                        Image(systemName: volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 11))
                    }
                    .buttonStyle(WidgetButtonStyle())
                    Slider(value: Binding(get: { volume.volume }, set: { volume.set($0) }), in: 0...1)
                        .controlSize(.mini)
                        .tint(tone)
                }
            }
        }
        .widgetPadding()
        .monitoring(if: context == .desktop, devices, volume)
    }
}

// MARK: - Microphone

struct MicrophoneWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var mic = MicrophoneMonitor.shared
    @ObservedObject private var devices = AudioDevicesMonitor.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let muted = context == .gallery ? false : mic.isMuted
        let tone = muted ? Color.red : style.tone(.green)
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "Microphone", symbol: "mic.fill", color: .green)
            HStack(spacing: 12) {
                Button(action: mic.toggleMute) {
                    Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(muted ? Color.white : tone)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(muted ? Color.red : tone.opacity(0.18)))
                }
                .buttonStyle(WidgetButtonStyle())
                .help(muted ? "Unmute microphone" : "Mute microphone")
                VStack(alignment: .leading, spacing: 2) {
                    Text(muted ? "Muted" : "Live").font(.system(size: 15, weight: .bold)).foregroundStyle(tone)
                    Text(context == .gallery ? "MacBook Pro Microphone" : (mic.deviceName.isEmpty ? "No microphone" : mic.deviceName))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if model.family != .small {
                HStack(spacing: 6) {
                    Image(systemName: "waveform").font(.system(size: 10)).foregroundStyle(.secondary)
                    Slider(value: Binding(get: { mic.volume }, set: { mic.set($0) }), in: 0...1)
                        .controlSize(.mini)
                        .tint(tone)
                        .disabled(!mic.hasVolume)
                    Menu {
                        ForEach(devices.devices.filter(\.hasInput)) { device in
                            Button { devices.select(device.id, input: true) } label: {
                                Label(device.name, systemImage: device.id == devices.input ? "checkmark" : device.symbol)
                            }
                        }
                    } label: { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)) }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                }
            }
        }
        .widgetPadding()
        .monitoring(if: context == .desktop, mic, devices)
    }
}

// MARK: - Keep awake

/// Stops the Mac (and its screen) from sleeping, like `caffeinate` or Amphetamine.
@MainActor
final class KeepAwake: ObservableObject {
    static let shared = KeepAwake()
    @Published private(set) var until: Date?
    @Published private(set) var isOn = false
    private var assertion: IOPMAssertionID = 0
    private var expiry: DispatchWorkItem?

    func turnOn(minutes: Int?) {
        if !isOn {
            let reason = "Home Widgets: Keep Awake" as CFString
            guard IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                              IOPMAssertionLevel(kIOPMAssertionLevelOn), reason, &assertion) == kIOReturnSuccess else { return }
            isOn = true
        }
        expiry?.cancel()
        if let minutes {
            until = Date().addingTimeInterval(TimeInterval(minutes * 60))
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.turnOff() } }
            expiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60), execute: work)
        } else {
            until = nil
        }
    }

    func turnOff() {
        expiry?.cancel()
        if isOn { IOPMAssertionRelease(assertion) }
        isOn = false
        until = nil
    }
}

struct KeepAwakeWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var awake = KeepAwake.shared
    @Environment(\.widgetStyle) private var style
    @Environment(\.widgetContext) private var context

    var body: some View {
        let on = context == .gallery ? true : awake.isOn
        let tone = style.tone(.brown)
        HStack(spacing: 12) {
            Button { on ? awake.turnOff() : awake.turnOn(minutes: nil) } label: {
                Image(systemName: on ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(on ? Color.white : tone)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(on ? tone : tone.opacity(0.15)))
                    .symbolEffect(.bounce, value: on)
            }
            .buttonStyle(WidgetButtonStyle())
            .disabled(context != .desktop)
            VStack(alignment: .leading, spacing: 4) {
                Text(on ? "Staying awake" : "Sleep as usual").font(.system(size: 13, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    Text(statusText(at: timeline.date)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if model.family != .small {
                    HStack(spacing: 5) {
                        ForEach([30, 60, 120, 240], id: \.self) { minutes in
                            Button { awake.turnOn(minutes: minutes) } label: {
                                Text(minutes < 60 ? "\(minutes)m" : "\(minutes / 60)h")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 34, height: 22)
                                    .background(Capsule().fill(tone.opacity(0.15)))
                            }
                            .buttonStyle(WidgetButtonStyle())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    private func statusText(at date: Date) -> String {
        if context == .gallery { return "Until you turn it off" }
        guard awake.isOn else { return "Tap the cup to keep your Mac awake" }
        guard let until = awake.until else { return "Until you turn it off" }
        let minutes = max(1, Int(until.timeIntervalSince(date) / 60))
        return "For \(Fmt.duration(minutes: minutes)) more"
    }
}

// MARK: - IP address

final class NetworkInfoMonitor: PollingMonitor {
    static let shared = NetworkInfoMonitor()
    @Published private(set) var local: [(name: String, address: String)] = []
    @Published private(set) var publicAddress: String?
    @Published private(set) var hostName = Host.current().localizedName ?? ""
    private var lastPublic = Date.distantPast

    override var interval: TimeInterval { 30 }

    override func sample() {
        let found = Self.localAddresses()
        if found.map(\.address) != local.map(\.address) {
            local = found
            lastPublic = .distantPast // network changed: look up the public address again
        }
        guard Date().timeIntervalSince(lastPublic) > 600, let url = URL(string: "https://api.ipify.org") else { return }
        lastPublic = Date()
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let text = data.flatMap { String(data: $0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { self?.publicAddress = text?.isEmpty == false ? text : nil }
        }.resume()
    }

    static func localAddresses() -> [(name: String, address: String)] {
        var out: [(String, String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(item.pointee.ifa_flags)
            guard let addr = item.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: item.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("utun") == false else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                out.append((name, String(cString: host)))
            }
        }
        return out
    }
}

struct IPAddressWidget: View {
    @ObservedObject var model: WidgetModel
    @ObservedObject private var info = NetworkInfoMonitor.shared
    @Environment(\.widgetContext) private var context
    @State private var copied: String?

    var body: some View {
        let local = context == .gallery ? [("en0", "192.168.1.24")] : info.local
        let external = context == .gallery ? "203.0.113.42" : info.publicAddress
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "IP Address", symbol: "network", color: .teal, trailing: copied == nil ? nil : "Copied")
            if model.family == .small {
                row("Local", local.first?.1 ?? "Not connected")
                row("Public", external ?? "…")
                Spacer(minLength: 0)
            } else {
                // Two columns, spread over the whole widget.
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        row("Local", local.first?.1 ?? "Not connected", large: true)
                        row("Public", external ?? "…", large: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 12) {
                        row("Mac", context == .gallery ? "Landon's MacBook Pro" : info.hostName, large: true)
                        row("Interface", local.first.map { $0.0 } ?? "—", large: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
        .widgetPadding()
        .monitoring(if: context == .desktop, info)
    }

    private func row(_ title: String, _ value: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: large ? 11 : 10, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: large ? 17 : 14, weight: .semibold, design: .monospaced)).fitLine(0.6)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            copyText(value)
            copied = value
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = nil }
        }
        .help("Click to copy")
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Internet (latency)

/// Measures how long a TCP handshake to Cloudflare's 1.1.1.1 takes — a decent "is the internet OK?" signal.
final class LatencyMonitor: PollingMonitor {
    static let shared = LatencyMonitor()
    @Published private(set) var latency: Double? // milliseconds; nil = offline
    @Published private(set) var history = MetricHistory(capacity: 40)
    @Published private(set) var lastCheck: Date?
    private var probing = false

    override var interval: TimeInterval { 10 }

    override func sample() {
        guard !probing else { return }
        probing = true
        let started = Date()
        let connection = NWConnection(host: "1.1.1.1", port: 443, using: .tcp)
        var finished = false
        let finish: (Double?) -> Void = { [weak self] value in
            guard !finished else { return }
            finished = true
            connection.cancel()
            DispatchQueue.main.async {
                guard let self else { return }
                self.probing = false
                self.latency = value
                self.lastCheck = Date()
                self.history.append(value ?? 0)
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready: finish(Date().timeIntervalSince(started) * 1000)
            case .failed, .cancelled: finish(nil)
            default: break
            }
        }
        connection.start(queue: .global(qos: .utility))
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { finish(nil) }
    }
}

struct InternetWidget: View {
    @ObservedObject var model: WidgetModel

    private static let sampleHistory: [Double] = (0..<40).map { (index: Int) -> Double in
        let wave: Double = 9 * sin(Double(index) * 0.7)
        return 18 + wave + Double(index % 5)
    }
    @ObservedObject private var monitor = LatencyMonitor.shared
    @Environment(\.widgetContext) private var context
    @Environment(\.widgetStyle) private var style

    var body: some View {
        let value = context == .gallery ? 18 : monitor.latency
        let color: Color = value == nil ? .red : value! < 60 ? .green : value! < 150 ? .yellow : .orange
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(title: "Internet", symbol: value == nil ? "wifi.exclamationmark" : "globe", color: color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { String(Int($0.rounded())) } ?? "Offline")
                    .font(.system(size: value == nil ? 22 : 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(style.tone(color))
                if value != nil { Text("ms").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
            }
            Text(value == nil ? "Can't reach the internet" : value! < 60 ? "Fast and steady" : value! < 150 ? "A little slow" : "Laggy right now")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            // The graph takes all the room left over.
            Sparkline(values: context == .gallery ? Self.sampleHistory : monitor.history.values,
                      color: color, maxValue: max(100, monitor.history.peak))
                .frame(minHeight: 26, maxHeight: .infinity)
        }
        .widgetPadding()
        .monitoring(if: context == .desktop, monitor)
    }
}

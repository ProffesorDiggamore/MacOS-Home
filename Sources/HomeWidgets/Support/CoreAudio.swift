import AudioToolbox
import CoreAudio
import Foundation

/// Small, synchronous wrappers around Core Audio. Reading a volume this way is a
/// few microseconds; the AppleScript `get volume settings` it replaces launched a
/// script interpreter on every sample.
enum AudioSystem {
    struct Device: Identifiable, Hashable {
        let id: AudioDeviceID
        let name: String
        let hasOutput: Bool
        let hasInput: Bool
        let transport: UInt32

        /// SF Symbol that suits the device.
        var symbol: String {
            let lower = name.lowercased()
            if lower.contains("airpods max") { return "airpodsmax" }
            if lower.contains("airpods pro") { return "airpodspro" }
            if lower.contains("airpods") { return "airpods" }
            if lower.contains("homepod") { return "homepod.fill" }
            if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return "headphones" }
            if transport == kAudioDeviceTransportTypeAirPlay { return "airplayaudio" }
            if transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort { return "tv" }
            if transport == kAudioDeviceTransportTypeUSB { return "cable.connector" }
            if hasInput && !hasOutput { return "mic.fill" }
            if lower.contains("headphone") { return "headphones" }
            return "hifispeaker.fill"
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID? {
        var address = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    static func setDefault(_ id: AudioDeviceID, input: Bool) {
        var address = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        if !input {
            // Keep alert sounds on the same device, like choosing it in Control Center does.
            var alerts = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &alerts, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        }
    }

    static func devices() -> [Device] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let output = channelCount(id, scope: kAudioObjectPropertyScopeOutput) > 0
            let input = channelCount(id, scope: kAudioObjectPropertyScopeInput) > 0
            guard output || input, let name = name(of: id) else { return nil }
            return Device(id: id, name: name, hasOutput: output, hasInput: input, transport: transport(of: id))
        }
    }

    static func name(of id: AudioDeviceID) -> String? {
        var address = address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let value = name?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func transport(of id: AudioDeviceID) -> UInt32 {
        var address = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }

    private static func channelCount(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    // MARK: Volume & mute

    private static func scope(_ input: Bool) -> AudioObjectPropertyScope {
        input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    }

    /// 0…1, or nil if the device has no volume control (e.g. HDMI).
    static func volume(of id: AudioDeviceID, input: Bool) -> Double? {
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope(input))
        if AudioObjectHasProperty(id, &address) {
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr { return Double(value) }
        }
        address = Self.address(kAudioDevicePropertyVolumeScalar, scope(input))
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? Double(value) : nil
    }

    static func setVolume(_ level: Double, of id: AudioDeviceID, input: Bool) {
        var value = Float32(min(1, max(0, level)))
        var address = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope(input))
        if AudioObjectHasProperty(id, &address) {
            AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
            return
        }
        address = Self.address(kAudioDevicePropertyVolumeScalar, scope(input))
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func isMuted(_ id: AudioDeviceID, input: Bool) -> Bool {
        var address = address(kAudioDevicePropertyMute, scope(input))
        guard AudioObjectHasProperty(id, &address) else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value != 0
    }

    static func setMuted(_ muted: Bool, _ id: AudioDeviceID, input: Bool) {
        var address = address(kAudioDevicePropertyMute, scope(input))
        guard AudioObjectHasProperty(id, &address) else { return }
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    // MARK: Change notifications

    /// Calls `handler` on the main queue whenever the property changes. Keep the token to stop.
    final class Listener {
        private let object: AudioObjectID
        private var address: AudioObjectPropertyAddress
        private let block: AudioObjectPropertyListenerBlock

        init?(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              handler: @escaping () -> Void) {
            self.object = object
            address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
            block = { _, _ in handler() }
            guard AudioObjectHasProperty(object, &address),
                  AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr else { return nil }
        }

        deinit {
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
    }

    static var systemObject: AudioObjectID { AudioObjectID(kAudioObjectSystemObject) }
}

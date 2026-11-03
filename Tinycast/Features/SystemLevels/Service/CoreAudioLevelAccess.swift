import AudioToolbox
import CoreAudio
import Foundation

struct CoreAudioLevelAccess: SystemAudioHardware {
    func output() -> SystemAudioState.Output? {
        guard let device = Self.defaultDevice(input: false) else { return nil }
        let controls = Self.volumeAddresses(device: device)
        let levels = controls.compactMap { Self.scalar(device, address: $0) }
        let volume = levels.count == controls.count && !levels.isEmpty
            ? levels.reduce(0, +) / Double(levels.count) : nil
        return .init(device: device, volume: volume, muted: Self.muted(device, input: false))
    }

    func microphone() -> SystemAudioState.Microphone? {
        guard let device = Self.defaultDevice(input: true) else { return nil }
        return .init(device: device, muted: Self.muted(device, input: true))
    }

    func writeVolume(_ volume: Double, device: UInt32) -> Bool {
        guard volume.isFinite, (0...1).contains(volume), Self.defaultDevice(input: false) == device else { return false }
        let addresses = Self.volumeAddresses(device: device)
        guard !addresses.isEmpty, addresses.allSatisfy({ Self.isSettable(device, address: $0) }) else { return false }
        for var address in addresses {
            guard Self.defaultDevice(input: false) == device else { return false }
            var value = Float32(volume)
            guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value)
                == noErr else { return false }
        }
        return true
    }

    func writeMute(_ muted: Bool, device: UInt32) -> Bool {
        guard Self.defaultDevice(input: false) == device else { return false }
        var address = Self.muteAddress(input: false)
        guard Self.isSettable(device, address: address) else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout.size(ofValue: value)), &value) == noErr
    }

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }

    static func defaultDevice(input: Bool) -> AudioDeviceID? {
        let selector = input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice
        var address = address(selector)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    static func muteAddress(input: Bool) -> AudioObjectPropertyAddress {
        address(kAudioDevicePropertyMute, scope: input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput)
    }

    static func volumeAddresses(device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        var virtual = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        if AudioObjectHasProperty(device, &virtual) { return [virtual] }
        var main = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
        if AudioObjectHasProperty(device, &main) { return [main] }
        var stereo = address(kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioDevicePropertyScopeOutput)
        var channels: [UInt32] = [1, 2]
        var size = UInt32(2 * MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &stereo, 0, nil, &size, &channels) == noErr else { return [] }
        return Array(Set(channels)).sorted().compactMap { channel in
            var address = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: channel)
            return AudioObjectHasProperty(device, &address) ? address : nil
        }
    }

    private static func isSettable(_ device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    private static func scalar(_ device: AudioDeviceID, address: AudioObjectPropertyAddress) -> Double? {
        var address = address
        var value: Float32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              value.isFinite, (0...1).contains(value) else { return nil }
        return Double(value)
    }

    private static func muted(_ device: AudioDeviceID, input: Bool) -> Bool? {
        var address = muteAddress(input: input)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout.size(ofValue: value))
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }
}

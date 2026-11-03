import CoreAudio
import Foundation

@MainActor
final class CoreMicrophoneAudio: MicrophoneAudioAccess {
    private typealias Audio = MicrophoneAudioObject

    private var topology: [Audio.Listener] = []
    private var controls: [Audio.Listener] = []
    private var change: (@MainActor () -> Void)?
    private(set) var monitoringFailure: MicrophoneInput.Failure?

    func inputs() throws(MicrophoneInput.Failure) -> [MicrophoneInput] {
        let devices = try Audio.list(Audio.system, Audio.address(kAudioHardwarePropertyDevices))
        var inputs: [MicrophoneInput] = []
        for device in devices {
            let channels = try channelCount(device)
            guard channels > 0 else { continue }
            guard let uid = try Audio.text(device, kAudioDevicePropertyDeviceUID), !uid.isEmpty else {
                throw .unavailable(String(device))
            }
            inputs.append(MicrophoneInput(
                id: device, uid: uid,
                mute: try levels(device, selector: kAudioDevicePropertyMute, channels: channels),
                volume: try levels(device, selector: kAudioDevicePropertyVolumeScalar, channels: channels)))
        }
        return inputs
    }

    func write(_ levels: [MicrophoneInput.Level], control: MicrophoneInput.Control,
               on input: MicrophoneInput) throws(MicrophoneInput.Failure) {
        guard MicrophoneInput.valid(levels) else { throw .changedControls(input.uid) }
        guard let current = try inputs().first(where: { $0.id == input.id && $0.uid == input.uid }) else {
            throw .unavailable(input.uid)
        }
        let before = control == .mute ? current.mute : current.volume
        guard Set(before.map(\.element)) == Set(levels.map(\.element)) else { throw .changedControls(input.uid) }
        let selector = control == .mute ? kAudioDevicePropertyMute : kAudioDevicePropertyVolumeScalar
        var written: [MicrophoneInput.Level] = []
        for level in levels {
            let property = Self.inputAddress(selector, element: level.element)
            guard try Audio.text(input.id, kAudioDevicePropertyDeviceUID) == input.uid,
                  Audio.isSettable(input.id, property) else { throw .unavailable(input.uid) }
            let status = control == .mute
                ? Audio.write(input.id, property, UInt32(level.value != 0 ? 1 : 0))
                : Audio.write(input.id, property, level.value)
            guard status == noErr else {
                for previous in before where written.contains(where: { $0.element == previous.element }) {
                    let rollback = Self.inputAddress(selector, element: previous.element)
                    if control == .mute {
                        _ = Audio.write(input.id, rollback, UInt32(previous.value != 0 ? 1 : 0))
                    } else {
                        _ = Audio.write(input.id, rollback, previous.value)
                    }
                }
                throw .write(input.uid, status)
            }
            written.append(level)
        }
    }

    func start(change: @escaping @MainActor () -> Void) {
        stop()
        self.change = change
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            topology.append(listener(Audio.system, Audio.address(selector)) { [weak self] in
                self?.rebuildListeners()
                self?.change?()
            })
        }
        rebuildListeners()
    }

    func stop() {
        change = nil
        topology = []
        controls = []
        monitoringFailure = nil
    }

    private func rebuildListeners() {
        guard change != nil else { return }
        controls = []
        monitoringFailure = topology.first(where: { $0.status != noErr }).map { .read($0.status) }
        do {
            for input in try inputs() {
                controls.append(listener(input.id, Self.inputAddress(kAudioDevicePropertyStreamConfiguration)) { [weak self] in
                    self?.rebuildListeners()
                    self?.change?()
                })
                for (selector, levels) in [(kAudioDevicePropertyMute, input.mute),
                                           (kAudioDevicePropertyVolumeScalar, input.volume)] {
                    for level in levels {
                        controls.append(listener(input.id, Self.inputAddress(selector, element: level.element)) { [weak self] in
                            self?.change?()
                        })
                    }
                }
            }
        } catch {
            monitoringFailure = error
        }
    }

    private func listener(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress,
                          change: @escaping @MainActor () -> Void) -> Audio.Listener {
        let listener = Audio.Listener(object, property, change: change)
        if listener.status != noErr { monitoringFailure = .read(listener.status) }
        return listener
    }

    private static func inputAddress(_ selector: AudioObjectPropertySelector,
                                     element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        Audio.address(selector, scope: kAudioDevicePropertyScopeInput, element: element)
    }

    private func levels(_ device: AudioObjectID, selector: AudioObjectPropertySelector,
                        channels: UInt32) throws(MicrophoneInput.Failure) -> [MicrophoneInput.Level] {
        let elements = Audio.isSettable(device, Self.inputAddress(selector)) ? [0] : Array(1...channels)
        guard elements.allSatisfy({ Audio.isSettable(device, Self.inputAddress(selector, element: $0)) }) else { return [] }
        return try elements.map { element throws(MicrophoneInput.Failure) in
            let property = Self.inputAddress(selector, element: element)
            let value: Float
            if selector == kAudioDevicePropertyMute {
                value = try Audio.read(device, property, initial: UInt32(0)) != 0 ? 1 : 0
            } else {
                value = try Audio.read(device, property, initial: Float(0))
            }
            guard value.isFinite, (0...1).contains(value) else { throw .read(kAudioHardwareIllegalOperationError) }
            return .init(element: element, value: value)
        }
    }

    private func channelCount(_ device: AudioObjectID) throws(MicrophoneInput.Failure) -> UInt32 {
        var property = Self.inputAddress(kAudioDevicePropertyStreamConfiguration)
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size)
        guard status == noErr else { throw .read(status) }
        guard size >= MemoryLayout<UInt32>.size, size <= 1_048_576 else {
            throw .read(kAudioHardwareBadPropertySizeError)
        }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        let result = AudioObjectGetPropertyData(device, &property, 0, nil, &size, memory)
        guard result == noErr else { throw .read(result) }
        let list = memory.assumingMemoryBound(to: AudioBufferList.self)
        let required = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers)! + Int(list.pointee.mNumberBuffers)
            * MemoryLayout<AudioBuffer>.stride
        guard required <= Int(size) else { throw .read(kAudioHardwareBadPropertySizeError) }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + $1.mNumberChannels }
    }
}

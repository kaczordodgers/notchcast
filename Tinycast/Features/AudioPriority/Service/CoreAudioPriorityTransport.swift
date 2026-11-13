// Adapted from Vorssaint (GPL-3.0-or-later)
import CoreAudio
import Foundation

@MainActor
final class CoreAudioPriorityTransport: AudioPriorityTransport {
    private struct Failure: Error {
        let status: OSStatus
    }

    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private let system = AudioObjectID(kAudioObjectSystemObject)

    func devices() throws -> [AudioPriorityDevice] {
        try deviceIDs().flatMap { id -> [AudioPriorityDevice] in
            var alive: UInt32 = 1
            var hidden: UInt32 = 0
            guard (try? read(id, kAudioDevicePropertyDeviceIsAlive, &alive)) != nil,
                  (try? read(id, kAudioDevicePropertyIsHidden, &hidden)) != nil else { return [] }
            guard alive != 0, hidden == 0 else { return [AudioPriorityDevice]() }
            var uid: CFString = "" as CFString
            guard (try? read(id, kAudioDevicePropertyDeviceUID, &uid)) != nil else { return [] }
            guard !(uid as String).isEmpty else { return [] }
            var name = uid
            _ = try? read(id, kAudioObjectPropertyName, &name)
            let privateAggregates = ["Vorssaint Mixer", "Vorssaint AirPlay",
                                     "Vorssaint Island Levels", "Vorssaint Recorder"]
            guard !privateAggregates.contains(name as String) else { return [] }
            return AudioPriorityDevice.Direction.allCases.compactMap { direction in
                let scope = scope(for: direction)
                var address = address(kAudioDevicePropertyStreams, scope: scope)
                var size: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr,
                      size >= MemoryLayout<AudioObjectID>.size else { return nil }
                var eligible: UInt32 = 1
                guard (try? read(id, kAudioDevicePropertyDeviceCanBeDefaultDevice,
                                 &eligible, scope: scope)) != nil else { return nil }
                guard eligible != 0 else { return nil }
                return AudioPriorityDevice(uid: uid as String, name: name as String,
                                           direction: direction)
            }
        }
    }

    func defaultUID(for direction: AudioPriorityDevice.Direction) throws -> String? {
        var id: AudioObjectID = 0
        try read(system, selector(for: direction), &id)
        guard id != 0 else { return nil }
        var uid: CFString = "" as CFString
        try read(id, kAudioDevicePropertyDeviceUID, &uid)
        return uid as String
    }

    func setDefault(uid: String, for direction: AudioPriorityDevice.Direction) throws {
        for id in try deviceIDs() {
            var candidate: CFString = "" as CFString
            guard (try? read(id, kAudioDevicePropertyDeviceUID, &candidate)) != nil else { continue }
            guard candidate as String == uid else { continue }
            var target = id
            var address = address(selector(for: direction))
            try check(AudioObjectSetPropertyData(system, &address, 0, nil,
                                                 UInt32(MemoryLayout.size(ofValue: target)), &target))
            return
        }
        throw Failure(status: kAudioHardwareBadDeviceError)
    }

    func start(onChange: @escaping @Sendable () -> Void) throws {
        guard listeners.count != 3 else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice,
                         kAudioHardwarePropertyDefaultInputDevice] {
            guard !listeners.contains(where: { $0.0.mSelector == selector }) else { continue }
            var address = address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            try check(AudioObjectAddPropertyListenerBlock(system, &address, .global(), block))
            listeners.append((address, block))
        }
    }

    func stop() throws {
        var retained: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
        var failure: OSStatus?
        for (var address, block) in listeners {
            let status = AudioObjectRemovePropertyListenerBlock(system, &address, .global(), block)
            if status != noErr {
                retained.append((address, block))
                failure = status
            }
        }
        listeners = retained
        if let failure { throw Failure(status: failure) }
    }

    private func deviceIDs() throws -> [AudioObjectID] {
        var address = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size))
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard !ids.isEmpty else { return [] }
        try ids.withUnsafeMutableBytes { buffer in
            try check(AudioObjectGetPropertyData(system, &address, 0, nil, &size, buffer.baseAddress!))
        }
        return ids
    }

    private func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         _ value: inout T,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws {
        var address = address(selector, scope: scope)
        var size = UInt32(MemoryLayout<T>.size)
        try withUnsafeMutablePointer(to: &value) { pointer in
            try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size,
                                                UnsafeMutableRawPointer(pointer)))
        }
    }

    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func scope(for direction: AudioPriorityDevice.Direction) -> AudioObjectPropertyScope {
        direction == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }

    private func selector(for direction: AudioPriorityDevice.Direction) -> AudioObjectPropertySelector {
        direction == .output ? kAudioHardwarePropertyDefaultOutputDevice
            : kAudioHardwarePropertyDefaultInputDevice
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw Failure(status: status) }
    }
}

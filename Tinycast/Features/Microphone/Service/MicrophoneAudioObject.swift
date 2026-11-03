import CoreAudio
import Foundation

@MainActor
enum MicrophoneAudioObject {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }

    static func read<T: BitwiseCopyable>(
        _ object: AudioObjectID, _ property: AudioObjectPropertyAddress, initial: T
    ) throws(MicrophoneInput.Failure) -> T {
        var property = property
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value)
        guard status == noErr else { throw .read(status) }
        guard size == MemoryLayout<T>.size else { throw .read(kAudioHardwareBadPropertySizeError) }
        return value
    }

    static func list(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress)
        throws(MicrophoneInput.Failure) -> [AudioObjectID] {
        var property = property
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(object, &property, 0, nil, &size)
        guard status == noErr else { throw .read(status) }
        guard size > 0 else { return [] }
        guard size <= 1_048_576, Int(size) % MemoryLayout<AudioObjectID>.stride == 0 else {
            throw .read(kAudioHardwareBadPropertySizeError)
        }
        var values = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        let result = values.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { throw .read(result) }
        return Array(values.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    static func text(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector)
        throws(MicrophoneInput.Failure) -> String? {
        var property = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout.size(ofValue: value))
        let status = AudioObjectGetPropertyData(object, &property, 0, nil, &size, &value)
        guard status == noErr else { throw .read(status) }
        return value?.takeRetainedValue() as String?
    }

    static func isSettable(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) -> Bool {
        var property = property
        var value: DarwinBoolean = false
        return AudioObjectHasProperty(object, &property)
            && AudioObjectIsPropertySettable(object, &property, &value) == noErr && value.boolValue
    }

    static func write<T: BitwiseCopyable>(
        _ object: AudioObjectID, _ property: AudioObjectPropertyAddress, _ value: T
    ) -> OSStatus {
        var property = property
        return withUnsafePointer(to: value) {
            AudioObjectSetPropertyData(object, &property, 0, nil, UInt32(MemoryLayout<T>.size), $0)
        }
    }

    @MainActor
    final class Listener {
        let status: OSStatus
        private let object: AudioObjectID
        private var property: AudioObjectPropertyAddress
        private let block: AudioObjectPropertyListenerBlock

        init(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress,
             change: @escaping @MainActor () -> Void) {
            self.object = object
            self.property = property
            let callback: AudioObjectPropertyListenerBlock = { @Sendable _, _ in Task { @MainActor in change() } }
            block = callback
            var registration = property
            status = AudioObjectAddPropertyListenerBlock(object, &registration, .main, callback)
        }

        isolated deinit {
            if status == noErr {
                AudioObjectRemovePropertyListenerBlock(object, &property, .main, block)
            }
        }
    }
}

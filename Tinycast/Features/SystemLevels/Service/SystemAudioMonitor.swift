import AudioToolbox
import CoreAudio
import Foundation
import OSLog

@MainActor
final class SystemAudioMonitor {
    private struct Listener {
        let device: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private static let log = Logger(subsystem: NotchcastIdentity.displayNameFallbackSubsystem, category: "SystemAudio")
    private var listeners: [Listener] = []
    private var generation = UUID()

    func start(state: SystemAudioState, changed: @escaping @MainActor () -> Void) {
        stop()
        let current = generation
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard self?.generation == current else { return }
                changed()
            }
        }
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice,
                         kAudioHardwarePropertyDevices] {
            listen(device: AudioObjectID(kAudioObjectSystemObject), address: CoreAudioLevelAccess.address(selector), block: block)
        }
        if let output = state.output {
            let addresses = [
                CoreAudioLevelAccess.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                             scope: kAudioDevicePropertyScopeOutput),
                CoreAudioLevelAccess.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
                                             element: kAudioObjectPropertyElementWildcard),
                CoreAudioLevelAccess.muteAddress(input: false),
            ]
            for address in addresses { listen(device: output.device, address: address, block: block) }
        }
        if let microphone = state.microphone {
            listen(device: microphone.device, address: CoreAudioLevelAccess.muteAddress(input: true), block: block)
        }
    }

    func stop() {
        generation = UUID()
        for var listener in listeners {
            AudioObjectRemovePropertyListenerBlock(listener.device, &listener.address, .main, listener.block)
        }
        listeners = []
    }

    private func listen(device: AudioObjectID, address: AudioObjectPropertyAddress,
                        block: @escaping AudioObjectPropertyListenerBlock) {
        var address = address
        guard address.mElement == kAudioObjectPropertyElementWildcard || AudioObjectHasProperty(device, &address) else { return }
        let status = AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        guard status == noErr else {
            Self.log.error("Audio property listener failed: \(status)")
            return
        }
        listeners.append(Listener(device: device, address: address, block: block))
    }

    isolated deinit { stop() }
}

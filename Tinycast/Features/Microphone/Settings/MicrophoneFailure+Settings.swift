import Foundation
import CoreAudio

extension MicrophoneInput.Failure {
    @MainActor var device: String {
        switch self {
        case .write(let uid, _), .unavailable(let uid), .unsupported(let uid), .changedControls(let uid):
            Self.deviceName(uid)
        default: String(localized: "Microphone")
        }
    }

    @MainActor private static func deviceName(_ uid: String) -> String {
        do {
            let devices = try MicrophoneAudioObject.list(
                MicrophoneAudioObject.system, MicrophoneAudioObject.address(kAudioHardwarePropertyDevices))
            for device in devices where try MicrophoneAudioObject.text(device, kAudioDevicePropertyDeviceUID) == uid {
                return try MicrophoneAudioObject.text(device, kAudioObjectPropertyName) ?? uid
            }
        } catch { return uid }
        return uid
    }

    var message: String {
        switch self {
        case .unsupported: String(localized: "The current microphone does not support software mute.")
        case .noInputs: String(localized: "No audio input device is available.")
        case .read(let status): String(localized: "macOS could not read microphone mute (error \(String(status))).")
        case .write(_, let status): String(localized: "macOS could not change microphone mute (error \(String(status))).")
        case .unavailable, .changedControls, .invalidSavedLevels:
            String(localized: "The microphone did not confirm the mute change. Try again.")
        }
    }
}

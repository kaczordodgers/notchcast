import Foundation

@MainActor
enum MicrophoneCommands {
    static func run(_ id: SystemAction.ID, preferences: NotchcastPreferences = .shared) -> Bool {
        guard id == .toggleMicrophoneMute else { return false }
        if preferences.isEnabled(.microphoneMute) {
            NotchcastCore.services?.microphone.toggle()
        }
        return true
    }
}

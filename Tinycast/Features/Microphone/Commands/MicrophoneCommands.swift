import Foundation

@MainActor
enum MicrophoneCommands {
    nonisolated static let launcherCommands = [
        NotchcastCommand(slug: "toggle-microphone-mute", name: String(localized: "Toggle Microphone Mute"),
                         sfSymbol: "mic.slash", isEnabled: {
                             NotchcastPreferences.shared.isEnabled(.microphoneMute)
                         }, run: { NotchcastCore.services?.microphone.toggle() })
    ]
}

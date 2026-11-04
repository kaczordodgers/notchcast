import Foundation

@MainActor
enum MicrophoneMuteCommands {
    nonisolated static let muteLauncherCommand =
        muteCommand("mute-microphone", name: String(localized: "Mute Microphone"), muted: true)
    nonisolated static let unmuteLauncherCommand =
        muteCommand("unmute-microphone", name: String(localized: "Unmute Microphone"), muted: false)

    nonisolated private static func muteCommand(_ slug: String, name: String, muted: Bool) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: name, sfSymbol: muted ? "mic.slash" : "mic", isEnabled: {
            NotchcastPreferences.shared.isEnabled(.microphoneMute)
        }, run: {
            guard NotchcastPreferences.shared.isEnabled(.microphoneMute) else { return }
            NotchcastCore.services?.microphone.setMuted(muted)
        })
    }
}

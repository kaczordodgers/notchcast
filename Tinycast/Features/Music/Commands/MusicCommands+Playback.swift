import Foundation

extension MusicCommands {
    nonisolated static let resumeLastPlayerCommand =
        NotchcastCommand(slug: "resume-last-player", name: String(localized: "Resume Last Player", table: "Notchcast"),
                         sfSymbol: "play", feature: .musicLastPlayer, isEnabled: {
                             NotchcastPreferences.shared.isEnabled(.musicLastPlayer)
                         }, run: { resumeLastPlayer() })
    nonisolated static let speakerOnCommand =
        speakerCommand("spotify-connect-speaker-on", name: String(localized: "Spotify Connect Speaker On", table: "Notchcast"), on: true)
    nonisolated static let speakerOffCommand =
        speakerCommand("spotify-connect-speaker-off", name: String(localized: "Spotify Connect Speaker Off", table: "Notchcast"), on: false)

    nonisolated private static func speakerCommand(_ slug: String, name: String, on: Bool) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: name, sfSymbol: "hifispeaker", feature: .spotifyConnect, isEnabled: { enabled }, run: {
            guard enabled else { return }
            let current = NotchcastPreferences.shared.isOn(.spotifyConnect)
            if current == on {
                AppCore.shared.showMessage(on
                    ? String(localized: "Spotify Connect Speaker is already on.", table: "Notchcast")
                    : String(localized: "Spotify Connect Speaker is already off.", table: "Notchcast"))
            } else if on {
                AppCore.shared.settingsCoordinator.showSettings(
                    tab: .notchcastMusicAndSound, revealing: .section(.notchcastSpotify))
            } else {
                NotchcastPreferences.shared.set(.spotifyConnect, false)
                AppCore.shared.showMessage(String(localized: "Spotify Connect Speaker is off.", table: "Notchcast"))
            }
        })
    }

    static func resumeLastPlayer() {
        guard NotchcastPreferences.shared.isEnabled(.musicLastPlayer),
              let model = NotchcastCore.services?.music.model else { return }
        guard model.nowPlaying != nil || model.canResume else { report(); return }
        model.send(.play)
    }
}

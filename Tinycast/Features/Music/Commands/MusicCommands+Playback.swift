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

    /// The speaker switch is what these commands flip, so they belong to Now Playing: Off must never hide On.
    nonisolated private static func speakerCommand(_ slug: String, name: String, on: Bool) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: name, sfSymbol: "hifispeaker", feature: .musicNowPlaying, isEnabled: { enabled }, run: {
            guard enabled else { return }
            let preferences = NotchcastPreferences.shared
            if on, (try? SpotifyConnectModule.shared?.key.isSaved) != true {
                preferences.set(.spotifyConnect, true)
                NotchcastHost.current.showSpotifySettings()
            } else if preferences.isOn(.spotifyConnect) == on {
                NotchcastHost.current.showMessage(on
                    ? String(localized: "Spotify Connect Speaker is already on.", table: "Notchcast")
                    : String(localized: "Spotify Connect Speaker is already off.", table: "Notchcast"), .success)
            } else {
                preferences.set(.spotifyConnect, on)
                NotchcastHost.current.showMessage(on
                    ? String(localized: "Starting…")
                    : String(localized: "Spotify Connect Speaker is off.", table: "Notchcast"), .success)
            }
        })
    }

    static func resumeLastPlayer() {
        guard NotchcastPreferences.shared.isEnabled(.musicLastPlayer),
              let model = MusicNowPlayingModule.shared?.model else { return }
        guard model.nowPlaying != nil || model.canResume else { report(); return }
        model.send(.play)
    }
}

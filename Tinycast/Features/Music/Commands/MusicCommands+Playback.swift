import Foundation

extension MusicCommands {
    nonisolated static let additionalLauncherCommands: [NotchcastCommand] = [
        NotchcastCommand(slug: "resume-last-player", name: String(localized: "Resume Last Player"),
                         sfSymbol: "play", isEnabled: {
                             NotchcastPreferences.shared.isEnabled(.musicLastPlayer)
                         }, run: { resumeLastPlayer() }),
        speakerCommand("spotify-connect-speaker-on", name: String(localized: "Spotify Connect Speaker On"), on: true),
        speakerCommand("spotify-connect-speaker-off", name: String(localized: "Spotify Connect Speaker Off"), on: false)
    ]

    nonisolated private static func speakerCommand(_ slug: String, name: String, on: Bool) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: name, sfSymbol: "hifispeaker", isEnabled: { enabled }, run: {
            guard enabled else { return }
            NotchcastPreferences.shared.set(.spotifyConnect, on)
        })
    }

    static func resumeLastPlayer() {
        guard NotchcastPreferences.shared.isEnabled(.musicLastPlayer),
              let model = NotchcastCore.services?.music.model else { return }
        guard model.canResume else { report(); return }
        model.send(.play)
    }
}

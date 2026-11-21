// notchcast-addon-order: 50
// notchcast-readme: Display & Sound: stop Apple Music opening on media keys
// notchcast-readme: Display & Sound: the play key resumes Spotify if you played it last
// notchcast-new-switch-ids: musicBlockResumeLastPlayer
import Foundation

/// Quits Apple Music when a media key, not the user, opened it, and plays the last player instead.
enum MusicBlockAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "musicBlockAppleMusic",
            title: String(localized: "Stop Apple Music opening on media keys", table: "NotchcastMusicBlock"),
            subtitle: "",
            category: .music, defaultEnabled: true, requiredGrants: [.accessibility]),
        NotchcastSwitch(
            id: "musicBlockResumeLastPlayer",
            title: String(localized: "Play key resumes the last player", table: "NotchcastMusicBlock"),
            subtitle: String(
                localized: "When nothing is playing, the play key resumes Spotify if you played it last.",
                table: "NotchcastMusicBlock"),
            category: .music, defaultEnabled: true, dependencies: ["musicBlockAppleMusic"],
            requiredGrants: [.accessibility]),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        MusicBlockModule(context: context)
    }
}

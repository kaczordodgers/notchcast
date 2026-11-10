import AppKit

@MainActor
enum MusicCommands {
    nonisolated static let launcherCommands: [NotchcastCommand] = [openCurrentPlayerCommand]
    nonisolated static let openCurrentPlayerCommand =
        NotchcastCommand(slug: "open-current-player", name: String(localized: "Open Current Player", table: "Notchcast"),
                         sfSymbol: "music.note", feature: .musicNowPlaying, isEnabled: { enabled }, run: { openCurrentPlayer() })

    static var enabled: Bool { NotchcastPreferences.shared.isEnabled(.musicNowPlaying) }

    static func send(_ command: PlayerCommand) {
        guard enabled, let music = MusicNowPlayingModule.shared else { return }
        let canStart = command == .togglePlayPause
            && (music.model.canResume || (music.soloist.isConnected && music.soloist.authState?.loggedIn == true))
        guard music.model.nowPlaying != nil || canStart else { report(); return }
        music.send(command)
    }

    static func openCurrentPlayer() {
        guard enabled, let music = MusicNowPlayingModule.shared else { return }
        guard let id = music.model.nowPlaying?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { report(); return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if error != nil { Task { @MainActor in report() } }
        }
    }

    static func report() {
        AppCore.shared.showMessage(String(localized: "The current player is unavailable.", table: "Notchcast"), tone: .danger)
    }
}

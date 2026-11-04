import AppKit

@MainActor
enum MusicCommands {
    nonisolated static let launcherCommands: [NotchcastCommand] = [
        command("play-pause", name: String(localized: "Play / Pause"), symbol: "playpause", action: .togglePlayPause),
        command("next-track", name: String(localized: "Next Track"), symbol: "forward.end", action: .next),
        command("previous-track", name: String(localized: "Previous Track"), symbol: "backward.end", action: .previous),
        NotchcastCommand(slug: "open-current-player", name: String(localized: "Open Current Player"),
                         sfSymbol: "music.note", isEnabled: { enabled }, run: { openCurrentPlayer() })
    ] + MicrophoneCommands.launcherCommands

    static var enabled: Bool { NotchcastPreferences.shared.isEnabled(.musicNowPlaying) }

    nonisolated private static func command(
        _ slug: String, name: String, symbol: String, action: PlayerCommand
    ) -> NotchcastCommand {
        NotchcastCommand(slug: slug, name: name, sfSymbol: symbol,
                         isEnabled: { enabled }, run: { send(action) })
    }

    static func send(_ command: PlayerCommand) {
        guard enabled, let music = NotchcastCore.services?.music else { return }
        let canStart = command == .togglePlayPause
            && (music.model.canResume || (music.soloist.isConnected && music.soloist.authState?.loggedIn == true))
        guard music.model.nowPlaying != nil || canStart else { report(); return }
        music.send(command)
    }

    static func openCurrentPlayer() {
        guard enabled, let music = NotchcastCore.services?.music else { return }
        guard let id = music.model.nowPlaying?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { report(); return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
            if error != nil { Task { @MainActor in report() } }
        }
    }

    static func report() {
        AppCore.shared.showMessage(String(localized: "The current player is unavailable."), tone: .danger)
    }
}

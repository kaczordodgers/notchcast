import AppKit
import Observation

@MainActor
enum MusicCommands {
    static func command(for id: SystemAction.ID) -> PlayerCommand? {
        switch id {
        case .playPause: .togglePlayPause
        case .nextTrack: .next
        case .previousTrack: .previous
        default: nil
        }
    }

    static func listed(_ results: AppIndex.Results,
                       preferences: NotchcastPreferences = .shared) -> AppIndex.Results {
        let music = preferences.isEnabled(.musicNowPlaying)
        let microphone = preferences.isEnabled(.microphoneMute)
        var filtered = results
        let keep: (AppEntry) -> Bool = { entry in
            if entry.id == CommandID.openCurrentPlayer.rawValue { return music }
            guard let action = SystemActionCatalog.action(forEntryID: entry.id) else { return true }
            if command(for: action.id) != nil { return music }
            return action.id != .toggleMicrophoneMute || microphone
        }
        filtered.favoriteCount = results.entries.prefix(results.favoriteCount).count(where: keep)
        filtered.matchCount = results.entries.prefix(results.matchCount).count(where: keep)
        let suggestions = results.favoriteCount + results.meetingCount
        filtered.suggestionCount = results.entries.dropFirst(suggestions)
            .prefix(results.suggestionCount).count(where: keep)
        filtered.entries = results.entries.filter(keep)
        return filtered
    }

    static func run(_ id: SystemAction.ID, core: AppCore,
                    preferences: NotchcastPreferences = .shared) -> Bool {
        guard let command = command(for: id) else { return false }
        guard preferences.isEnabled(.musicNowPlaying),
              let music = NotchcastCore.services?.music else { return true }
        let canStart = command == .togglePlayPause
            && (music.model.canResume || (music.soloist.isConnected && music.soloist.authState?.loggedIn == true))
        guard music.model.nowPlaying != nil || canStart else {
            report(core: core)
            return true
        }
        music.send(command)
        return true
    }

    static func openCurrentPlayer(core: AppCore) {
        guard NotchcastPreferences.shared.isEnabled(.musicNowPlaying),
              let music = NotchcastCore.services?.music else { return }
        guard let id = music.model.nowPlaying?.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            report(core: core)
            return
        }
        Task {
            do {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: .init())
            } catch {
                report(core: core)
            }
        }
    }

    static func report(core: AppCore) {
        core.showMessage(String(localized: "The current player is unavailable."), tone: .danger)
    }
}

@MainActor
final class MusicCommandFeedback {
    private let music: MusicNowPlayingModule
    private weak var core: AppCore?
    private var lastFailure: MusicModel.Failure?

    init(music: MusicNowPlayingModule, core: AppCore) {
        self.music = music
        self.core = core
        observe()
    }

    private func observe() {
        withObservationTracking {
            let failure = music.model.failure
            if music.model.isEnabled, failure != nil, failure != lastFailure, let core {
                MusicCommands.report(core: core)
            }
            lastFailure = failure
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observe() }
        }
    }
}

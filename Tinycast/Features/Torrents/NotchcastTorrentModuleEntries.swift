import Foundation

extension NotchcastCore {
    static let torrents = TorrentModule(
        session: TorrentAria2Session(stateDirectory: AppPaths.applicationSupport().appending(path: "Torrents")))
}

extension AppCore {
    func handleTorrentURL(_ url: URL) -> Bool {
        guard TorrentModule.accepts(url) else { return false }
        if !NotchcastCore.torrents.preferences.isOn(.torrents) {
            showMessage(String(localized: "Torrents is off in Settings > Notchcast."))
            return true
        }
        return NotchcastCore.torrents.open(url)
    }
}

import Foundation

extension AppCore {
    func handleTorrentURL(_ url: URL) -> Bool {
        guard TorrentModule.accepts(url) else { return false }
        if !NotchcastCore.torrents.preferences.isOn(.torrents) {
            showMessage(String(localized: "Torrents is off in Settings > Notchcast.", table: "Notchcast"))
            return true
        }
        return NotchcastCore.torrents.open(url)
    }
}

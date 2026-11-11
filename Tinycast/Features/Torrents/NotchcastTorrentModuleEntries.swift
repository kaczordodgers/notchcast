import Foundation

extension AppCore {
    func handleTorrentURL(_ url: URL) -> Bool {
        guard TorrentModule.accepts(url) else { return false }
        if !TorrentModule.shared.preferences.isOn(.torrents) {
            showMessage(String(localized: "Torrents is off in Settings > Notchcast.", table: "Notchcast"))
            return true
        }
        return TorrentModule.shared.open(url)
    }
}

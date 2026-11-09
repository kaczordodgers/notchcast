import Foundation

extension NotchcastFeature.Descriptor {
    static let torrents = Self(
        title: String(localized: "Torrents", table: "Notchcast"),
        subtitle: String(localized: "Download magnet links and torrent files to Downloads.", table: "Notchcast"),
        group: .torrents,
        defaultEnabled: true,
        dependencies: [],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}

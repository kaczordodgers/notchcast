import Foundation

extension NotchcastFeature.BackupKeys {
    static let machRemote = Self(allowed: [:], excluded: [
        "remoteMacAddress",
        "remoteTerminalDirectory",
        "remoteUpdatePath",
    ])
}

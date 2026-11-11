import Foundation

extension NotchcastFeature.BackupKeys {
    static let machRemote = Self(allowed: [:], excluded: [
        NotchcastPreferences.remoteMacAddressKey,
        NotchcastPreferences.remoteTerminalDirectoryKey,
        NotchcastPreferences.remoteUpdatePathKey,
    ])
}

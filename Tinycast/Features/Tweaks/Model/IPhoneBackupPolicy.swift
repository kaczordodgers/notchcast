import Foundation

nonisolated enum IPhoneBackupPolicy {
    static func writes(automaticBackups: Bool) -> [TypingPreferencePlan.Write] {
        [.init("com.apple.AMPDevicesClient", "AutomaticDeviceBackupsDisabled", .bool(!automaticBackups))]
    }

    static func backupDirectory(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/MobileSync/Backup", isDirectory: true)
    }
}

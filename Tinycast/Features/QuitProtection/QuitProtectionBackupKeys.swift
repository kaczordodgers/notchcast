import Foundation

extension NotchcastFeature.BackupKeys {
    static let quitProtection = Self(allowed: [
        "notchcast.quitProtection.quitEnabled": .bool,
        "notchcast.quitProtection.closeEnabled": .bool,
        "notchcast.quitProtection.mode": .string(11, ["hold", "doublePress"]),
        "notchcast.quitProtection.exceptions": .strings(500, 256),
    ], excluded: [])
}

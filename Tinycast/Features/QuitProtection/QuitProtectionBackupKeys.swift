import Foundation

extension NotchcastFeature.BackupKeys {
    static let quitProtection = Self(allowed: [
        "notchcast.quitProtection.quitEnabled": .bool,
        "notchcast.quitProtection.closeEnabled": .bool,
        "notchcast.quitProtection.mode": .string(11, ["hold", "doublePress"]),
        "notchcast.quitProtection.exceptions": .strings(500, 256),
    ], excluded: [], snapshot: { QuitProtectionStore.shared.backupValues },
       apply: { QuitProtectionStore.shared.applyBackup($0) })
}

extension QuitProtectionStore {
    var backupValues: [String: Any] {
        ["notchcast.quitProtection.quitEnabled": configuration.quitEnabled,
         "notchcast.quitProtection.closeEnabled": configuration.closeEnabled,
         "notchcast.quitProtection.mode": configuration.mode.rawValue,
         "notchcast.quitProtection.exceptions": configuration.exceptions.sorted()]
    }

    func applyBackup(_ values: [String: Any]) {
        guard values.keys.contains(where: { $0.hasPrefix("notchcast.quitProtection.") }) else { return }
        var configuration = configuration
        if let value = values["notchcast.quitProtection.quitEnabled"] as? Bool { configuration.quitEnabled = value }
        if let value = values["notchcast.quitProtection.closeEnabled"] as? Bool { configuration.closeEnabled = value }
        if let value = values["notchcast.quitProtection.mode"] as? String,
           let mode = QuitProtectionEngine.Mode(rawValue: value) { configuration.mode = mode }
        if let value = values["notchcast.quitProtection.exceptions"] as? [String] { configuration.exceptions = Set(value) }
        self.configuration = configuration
    }
}

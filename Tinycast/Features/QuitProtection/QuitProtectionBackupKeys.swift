import Foundation

extension NotchcastFeature.BackupKeys {
    static let quitProtection = Self(allowed: [
        QuitProtectionStore.quitEnabledKey: .bool,
        QuitProtectionStore.closeEnabledKey: .bool,
        QuitProtectionStore.modeKey: .string(11, QuitProtectionEngine.Mode.allCases.map(\.rawValue)),
        QuitProtectionStore.exceptionsKey: .strings(500, 256),
    ], excluded: [], snapshot: { QuitProtectionStore.shared.backupValues },
       apply: { QuitProtectionStore.shared.applyBackup($0) })
}

extension QuitProtectionStore {
    var backupValues: [String: Any] {
        [QuitProtectionStore.quitEnabledKey: configuration.quitEnabled,
         QuitProtectionStore.closeEnabledKey: configuration.closeEnabled,
         QuitProtectionStore.modeKey: configuration.mode.rawValue,
         QuitProtectionStore.exceptionsKey: configuration.exceptions.sorted()]
    }

    func applyBackup(_ values: [String: Any]) {
        guard NotchcastFeature.BackupKeys.quitProtection.allowed.keys.contains(where: { values[$0] != nil }) else { return }
        var configuration = configuration
        if let value = values[QuitProtectionStore.quitEnabledKey] as? Bool { configuration.quitEnabled = value }
        if let value = values[QuitProtectionStore.closeEnabledKey] as? Bool { configuration.closeEnabled = value }
        if let value = values[QuitProtectionStore.modeKey] as? String,
           let mode = QuitProtectionEngine.Mode(rawValue: value) { configuration.mode = mode }
        if let value = values[QuitProtectionStore.exceptionsKey] as? [String] { configuration.exceptions = Set(value) }
        self.configuration = configuration
    }
}

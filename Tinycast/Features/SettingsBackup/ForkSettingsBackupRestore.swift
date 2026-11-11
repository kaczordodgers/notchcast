import Foundation

/// The feature switches of a backup; every other key is saved and restored by its feature's `BackupKeys`.
@MainActor
enum ForkSettingsBackupRestore {
    static func snapshot(_ preferences: NotchcastPreferences) -> [String: Any] {
        switches.reduce(into: [:]) { $0[$1.rawValue] = carried($1, preferences.isOn($1)) }
    }

    static func apply(_ values: [String: Any], to preferences: NotchcastPreferences) throws {
        try ForkSettingsBackupEngine.validate(values)
        for feature in switches {
            if let enabled = values[feature.rawValue] as? Bool { preferences.set(feature, carried(feature, enabled)) }
        }
    }

    private static let switches = NotchcastFeature.allCases.filter {
        ForkSettingsBackupSchema.allowed[$0.rawValue] != nil
    }

    /// An unwired switch is carried as off both ways, so a restore cannot enable a hidden feature.
    private static func carried(_ feature: NotchcastFeature, _ enabled: Bool) -> Bool { feature.isWired && enabled }
}

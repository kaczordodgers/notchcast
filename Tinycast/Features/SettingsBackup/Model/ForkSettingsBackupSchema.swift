import Foundation

enum ForkSettingsBackupSchema {
    static let allowed = NotchcastFeature.BackupKeys.all.reduce(into: switches(true)) {
        $0.merge($1.allowed) { _, _ in preconditionFailure("A backup key is declared twice") }
    }
    static let excluded = NotchcastFeature.BackupKeys.all.reduce(into: Set(switches(false).keys)) { $0.formUnion($1.excluded) }

    /// A switch is a backup key under its raw value, carried or left out as the feature's `backedUp` says.
    private static func switches(_ backedUp: Bool) -> [String: NotchcastFeature.BackupValue] {
        NotchcastFeature.allCases.reduce(into: [:]) {
            if $1.backedUp == backedUp { $0[$1.rawValue] = .bool }
        }
    }
}

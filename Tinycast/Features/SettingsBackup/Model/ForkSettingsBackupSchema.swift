import Foundation

enum ForkSettingsBackupSchema {
    static let allowed = NotchcastFeature.BackupKeys.all.reduce(into: switches(true)) {
        $0.merge($1.allowed) { _, _ in preconditionFailure("A backup key is declared twice") }
    }
    static let excluded = NotchcastFeature.BackupKeys.all.reduce(into: Set(switches(false).keys)) { $0.formUnion($1.excluded) }

    /// A switch is a backup key under its raw value, carried or left out as the feature's `backedUp` says.
    private static func switches(_ backedUp: Bool) -> [String: NotchcastFeature.BackupValue] {
        NotchcastFeature.allCases.reduce(into: [:]) {
            if ($1.backedUp ?? switchesAwaitingFlag[$1]) == backedUp { $0[$1.rawValue] = .bool }
        }
    }

    /// Features whose descriptor does not state `backedUp` yet; delete a line once its descriptor does.
    private static let switchesAwaitingFlag: [NotchcastFeature: Bool] = [
        .archives: false,
        .archivesDefaultApp: false,
        .archivesInPlace: false,
        .clearNotifications: false,
        .copyPath: true,
        .finderCutPaste: true,
        .finderRename: true,
        .quickLookSpace: true,
        .pasteImage: true,
        .pastePlain: true,
        .smallCommands: false,
        .torrents: false,
        .torrentsKeepSharing: false,
        .torrentsUseIPhone: false,
    ]
}

/// A feature's live settings-backup values, from `<Name>BackupState.swift` in its own folder.
@MainActor
struct NotchcastBackupState {
    let snapshot: () -> [String: Any]
    let apply: ([String: Any]) -> Void

    /// One feature per line, so branches that add features merge by union.
    static let all: [Self] = [
        .screenText,
        .liveTimers,
        .quitProtection,
        .dayCalendar,
    ]
}

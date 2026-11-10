import Foundation

@MainActor
struct ForkSettingsBackupState {
    let snapshot: () throws -> [String: Any]
    let validate: ([String: Any]) throws -> Void
    let apply: ([String: Any]) throws -> Void
}

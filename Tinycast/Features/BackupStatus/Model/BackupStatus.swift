import Foundation

struct BackupStatus: Decodable, Sendable, Equatable {
    enum Result: String, Decodable, Sendable { case ok, warning, failed, skipped }

    struct RestoreTest: Decodable, Sendable, Equatable {
        let at: Date
        let result: Result
    }

    struct TimeMachine: Decodable, Sendable, Equatable {
        let latest: Date?
        let checkedAt: Date?
        let error: String?
    }

    let version: Int
    let result: Result
    let message: String?
    let lastSuccess: Date?
    let lastAttempt: Date
    let snapshotCount: Int
    let oldestSnapshot: Date?
    let newestSnapshot: Date?
    let sourceBytes: Int64?
    let addedBytes: Int64?
    let repoBytes: Int64?
    let targetFreeBytes: Int64?
    let lowSpace: Bool
    let retention: String?
    let restoreTest: RestoreTest?
    let mbpTimeMachine: TimeMachine?
}

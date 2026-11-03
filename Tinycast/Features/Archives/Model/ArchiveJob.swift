import Foundation

nonisolated struct ArchiveJob: Identifiable, Equatable, Sendable {
    enum State: Equatable, Sendable {
        case queued, preflighting, extracting, cancelling, finished, failed, cancelled
    }

    let id: UUID
    let archive: URL
    var state: State = .queued
    var bytesWritten: Int64 = 0
    var totalBytes: Int64 = 0
    var output: URL?
    var failure: ArchiveFailure?
}

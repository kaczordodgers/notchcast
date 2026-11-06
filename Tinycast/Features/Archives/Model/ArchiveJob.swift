import Foundation

nonisolated struct ArchiveJob: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case extraction
        case compression(ArchiveCompression, [URL])
    }
    enum State: Equatable, Sendable {
        case queued, preflighting, extracting, cancelling, finished, failed, cancelled
    }

    enum Mode: Equatable, Sendable { case keepArchive, inPlace }

    enum Fallback: Equatable, Sendable {
        case inPlaceCheckRefused(Int32)
        case resumingKeepArchive
    }

    struct Recovery: Equatable, Sendable {
        let staging: URL
        let totalBytes: Int64
        let quarantine: Data?
        var readyToPublish = false
    }

    let id: UUID
    let archive: URL
    var kind: Kind = .extraction
    var mode: Mode = .keepArchive
    var effectiveMode: Mode = .keepArchive
    var fallback: Fallback?
    var state: State = .queued
    var bytesWritten: Int64 = 0
    var totalBytes: Int64 = 0
    var output: URL?
    var failure: ArchiveFailure?
    var recovery: Recovery?
}

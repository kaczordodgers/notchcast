import Foundation

struct CleanHistoryEntry: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable {
        case trashed, refused, failed, restored
    }

    let time: Date
    let mode: String
    let size: Int64
    let status: Status
    let originalPath: String
    let trashPath: String
}

enum CleanHistoryError: Error, Equatable {
    case invalidPath, destinationExists, trashMissing, parentMissing, symbolicLink
    case system(Int32), recordTooLarge
}

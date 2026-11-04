import Foundation

struct CleanOutcome: Sendable {
    enum Status: Sendable, Equatable {
        case trashed, changedOrMissing, refused, failed(String)
    }

    let item: CleanItem
    let status: Status
    let bytesMoved: Int64
    // Moving to Trash retains the bytes on the volume.
    let bytesFreed: Int64 = 0
}

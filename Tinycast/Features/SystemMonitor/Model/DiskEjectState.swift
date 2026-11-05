import Foundation

nonisolated enum DiskEjectState: Sendable {
    case idle
    case ejecting
    case failed(any Error)
}

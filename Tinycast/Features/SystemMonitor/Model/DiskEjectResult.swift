import Foundation

nonisolated enum DiskEjectResult: Sendable {
    case ejected
    case busy(any Error)
    case notEjectable
    case gone
}

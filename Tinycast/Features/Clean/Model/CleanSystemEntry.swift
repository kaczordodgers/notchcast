import Foundation

struct CleanSystemEntry: Sendable, Equatable {
    let path: String
    let size: Int64
    let modified: Date
    let identity: String
    let isRegularFile: Bool
    let hasSymlinkComponent: Bool
}

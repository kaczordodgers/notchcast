import Foundation

struct CleanDiskScan: Sendable {
    struct Node: Sendable {
        let path: URL
        let parent: Int?
        let directory: Bool
        let device: UInt64
        let inode: UInt64
        var allocatedSize: UInt64
        var unreadable: Bool = false
    }

    let id: UUID
    let root: URL
    let capturedAt: Date
    let nodes: [Node]
    let largestFiles: [Int]
    let limited: Bool
}

import Foundation

struct CleanItem: Sendable {
    let category: CleanCategory
    let path: URL
    let size: Int64
    let reportOnly: Bool
    internal let snapshot: [String: String]
}

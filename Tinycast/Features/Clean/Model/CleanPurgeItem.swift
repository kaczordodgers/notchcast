import Foundation

struct CleanPurgeItem: Sendable {
    enum Activity: Sendable { case idle, active, unknown }

    let project: URL
    let path: URL
    let rule: CleanPurgeRule
    let allocatedSize: Int64
    let activity: Activity
    let recentlyActive: Bool
    var selectedByDefault: Bool { activity == .idle && !recentlyActive }
    internal let authority: UUID
    internal let snapshot: [String: String]
}

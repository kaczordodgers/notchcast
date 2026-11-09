import Foundation

struct TodoAgentClaim: Codable, Equatable, Sendable {
    let agent: String
    let claimedAt: Date
    var lastActivityAt: Date
    let previousSectionID: String?
    let claimSectionID: String?
}

import Foundation

struct AgentAnswerItem: Equatable, Sendable {
    enum Source: Sendable { case t3, bot }
    let id: String
    let revision: String
    let source: Source
    let question: String
    var choices: [String] = []
    var allowsApprove = false
    var allowsDeny = false
}

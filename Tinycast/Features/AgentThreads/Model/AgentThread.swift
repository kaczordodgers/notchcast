import Foundation

struct AgentThread: Identifiable, Equatable, Sendable {
    enum Phase: String, CaseIterable, Sendable {
        case starting
        case running
        case waitingForApproval
        case waitingForInput
        case completed
        case failed
        case stale

        var waiting: Bool { self == .waitingForApproval || self == .waitingForInput }
        var finished: Bool { self == .completed || self == .failed || self == .stale }
    }

    let id: String
    let title: String
    let project: String
    let model: String
    var phase: Phase
    var pendingCount: Int
    let link: URL
    let updatedAt: Date
    let settled: Bool
}

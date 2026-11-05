import Foundation

struct AgentIslandEngine: Sendable {
    enum Source: Sendable { case t3, openBot }
    enum Mode: Equatable, Sendable {
        case approval(Int), question(Int), failed(String), working(names: [String], total: Int)
        case finished(String), idle
    }
    struct Presentation: Equatable, Sendable {
        var t3: Mode = .idle
        var openBot: Mode = .idle
        var waiting = 0
        var working = 0
        var message: Message {
            waiting == 0 && working == 0 ? .idle : .counts(waiting: waiting, working: working)
        }
    }
    enum Message: Equatable, Sendable { case idle, counts(waiting: Int, working: Int) }

    private var dismissed: [String: AgentThread] = [:]
    private(set) var presentation = Presentation()

    mutating func dismissFailed(_ thread: AgentThread) {
        if thread.phase == .failed { dismissed[thread.id] = thread }
    }

    mutating func update(threads: [AgentThread], pending: [String: OpenBotPending],
                         t3Enabled: Bool, openBotEnabled: Bool, now: Date) {
        let threads = t3Enabled ? threads.sorted { $0.id < $1.id } : []
        dismissed = dismissed.filter { id, value in threads.contains { $0.id == id && $0 == value } }
        let approvals = threads.filter { $0.phase == .waitingForApproval }
            .reduce(0) { $0 + max(1, $1.pendingCount) }
        let questions = threads.filter { $0.phase == .waitingForInput }.count
        let working = threads.filter { $0.phase == .running || $0.phase == .starting }
        let pending = openBotEnabled ? Array(pending.values) : []
        let botApprovals = pending.reduce(0) { $0 + $1.approvals.count + $1.browserTakeovers.count }
        let botQuestions = pending.reduce(0) { $0 + $1.prompts.count }
        var result = Presentation()
        if approvals > 0 {
            result.t3 = .approval(approvals)
        } else if questions > 0 {
            result.t3 = .question(questions)
        } else if let failed = threads.first(where: { $0.phase == .failed && dismissed[$0.id] != $0 }) {
            result.t3 = .failed(failed.title)
        } else if !working.isEmpty {
            result.t3 = .working(names: working.prefix(3).map(\.title), total: working.count)
        } else if let finished = threads.filter({
            $0.phase == .completed && now >= $0.updatedAt && now.timeIntervalSince($0.updatedAt) < 5.2
        }).max(by: { $0.updatedAt < $1.updatedAt }) {
            result.t3 = .finished(finished.title)
        }
        if botApprovals > 0 {
            result.openBot = .approval(botApprovals)
        } else if botQuestions > 0 {
            result.openBot = .question(botQuestions)
        }
        result.waiting = approvals + questions + botApprovals + botQuestions
        result.working = working.count
        presentation = result
    }
}

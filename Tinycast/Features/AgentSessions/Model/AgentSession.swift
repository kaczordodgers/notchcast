import Foundation

struct AgentSession: Identifiable, Sendable, Equatable {
    enum Provider: String, Sendable, CaseIterable {
        case claude, codex, copilot, opencode
    }

    struct Tokens: Sendable, Equatable {
        var input: Int64 = 0
        var cacheRead: Int64 = 0
        var cacheWrite: Int64 = 0
        var output: Int64 = 0
        var reasoning: Int64 = 0

        static func + (left: Self, right: Self) -> Self {
            var result = left
            result += right
            return result
        }

        static func += (left: inout Self, right: Self) {
            left = Self(input: sum(left.input, right.input), cacheRead: sum(left.cacheRead, right.cacheRead),
                 cacheWrite: sum(left.cacheWrite, right.cacheWrite), output: sum(left.output, right.output),
                 reasoning: sum(left.reasoning, right.reasoning))
        }

        func growth(after previous: Self) -> Self {
            Self(input: max(0, input - previous.input), cacheRead: max(0, cacheRead - previous.cacheRead),
                 cacheWrite: max(0, cacheWrite - previous.cacheWrite), output: max(0, output - previous.output),
                 reasoning: max(0, reasoning - previous.reasoning))
        }

        private static func sum(_ left: Int64, _ right: Int64) -> Int64 {
            let (value, overflow) = left.addingReportingOverflow(right)
            return overflow ? .max : value
        }
    }

    struct Usage: Sendable, Equatable {
        let model: String?
        let day: Date
        var tokens: Tokens
        var reportedCost: Double?
    }

    var id: String
    let provider: Provider
    var project: String?
    var startedAt: Date?
    var endedAt: Date?
    var lastActivityAt: Date?
    var model: String?
    var usage: [Usage] = []

    func isWorking(at now: Date) -> Bool {
        endedAt == nil && lastActivityAt.map { now.timeIntervalSince($0) < 600 } == true
    }
}

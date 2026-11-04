import Foundation

struct AgentReply: Codable, Equatable, Sendable {
    enum Code: String, Codable, Error, Sendable {
        case ok, failed, badRequest, notRunning, declined

        var exit: Int32 {
            switch self {
            case .ok: 0
            case .failed: 1
            case .badRequest: 2
            case .notRunning: 3
            case .declined: 5
            }
        }
    }

    var code: Code
    var result: AgentJSON = .null
}

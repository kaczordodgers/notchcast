import Foundation

enum AgentRequestTiming {
    static let serverTimeout: Duration = .seconds(30)
    static let confirmationTimeout = serverTimeout - .seconds(5)
}

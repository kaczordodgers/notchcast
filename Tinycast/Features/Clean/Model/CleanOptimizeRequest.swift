import Foundation

struct CleanOptimizeRequest: Equatable, Sendable {
    let executable: URL
    let arguments: [String]
    let timeout: TimeInterval
    let environment: [String: String] = [:]

    enum Result: Equatable, Sendable {
        case exited(Int32)
        case timedOut
        case failed
    }
}

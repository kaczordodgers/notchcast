import Foundation

struct CleanAIDataOutcome: Sendable {
    enum Status: Equatable, Sendable {
        case trashed, refused, changed, recoveryFailed, failed(String)
    }
    let path: URL
    let status: Status
    let recovery: URL?
}

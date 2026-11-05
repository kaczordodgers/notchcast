import Foundation

enum SoloistSpeakerState: Equatable, Sendable {
    case off
    case noKey
    case needsBuild
    case downloading
    case starting
    case running(port: Int)
    case waitingForOther
    case expiresSoon(days: Int)
    case failed(reason: SoloistFailure)
}

enum SoloistFailure: Error, Equatable, Sendable {
    case keyUnavailable
    case keyNotSaved
    case invalidKey
    case keyFileUnreadable
    case download
    case httpStatus(Int)
    case archive
    case unpack
    case refusedBuild
    case process
    case portTimeout
    case filesystem
    /// A failure plus what went wrong underneath (the step, the OS error), shown after its message.
    indirect case detailed(SoloistFailure, String)

    var reason: SoloistFailure {
        if case .detailed(let failure, _) = self { failure.reason } else { self }
    }

    func detail(_ text: String) -> SoloistFailure { .detailed(reason, text) }

    /// The OS error behind a failure, with its domain and code so a report pins it down.
    static func describe(_ error: any Error) -> String {
        if let failure = error as? SoloistFailure {
            if case .detailed(_, let text) = failure { return text }
            return String(describing: failure)
        }
        let error = error as NSError
        return "\(error.localizedDescription) (\(error.domain) \(error.code))"
    }
}

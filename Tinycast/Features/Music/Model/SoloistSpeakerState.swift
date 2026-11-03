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
    case invalidKey
    case keyFileUnreadable
    case download
    case httpStatus(Int)
    case retryAfter(Date)
    case archive
    case refusedBuild
    case process
    case portTimeout
    case filesystem
}

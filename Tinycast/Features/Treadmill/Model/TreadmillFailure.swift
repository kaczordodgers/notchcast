import Foundation

enum TreadmillFailure: Error, Equatable, Sendable {
    case disabled, unavailable, notReady, alreadyWalking, noWalk, notPaused, notRunning
    case invalidSpeed, invalidMinutes, timedOut, padError(UInt8), invalidHistory
}

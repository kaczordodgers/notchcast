import Foundation

enum TreadmillFailure: LocalizedError, Equatable, Sendable {
    case disabled, unavailable, notReady, alreadyWalking, noWalk, notPaused, notRunning
    case invalidSpeed, invalidMinutes, timedOut, padError(UInt8), invalidHistory

    var errorDescription: String? {
        switch self {
        case .disabled: String(localized: "Walking pad controls are turned off.")
        case .unavailable: String(localized: "The walking pad is not connected.")
        case .notReady: String(localized: "The walking pad is not ready.")
        case .alreadyWalking: String(localized: "A walk is already in progress.")
        case .noWalk: String(localized: "There is no walk in progress.")
        case .notPaused: String(localized: "The walk is not paused.")
        case .notRunning: String(localized: "The walk is not running.")
        case .invalidSpeed: String(localized: "Choose a speed supported by the walking pad.")
        case .invalidMinutes: String(localized: "Choose a valid walk duration.")
        case .timedOut: String(localized: "The walking pad did not respond in time.")
        case .padError: String(localized: "The walking pad reported an error.")
        case .invalidHistory: String(localized: "The walk history could not be read.")
        }
    }
}
